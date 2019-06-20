xontrib load schedule
import types
try:
    import ujson as json
except ImportError:
    import json
import cumin
import collections.abc

__all__ = 'salt',


salt_client = None

exec_modules = {}
runner_modules = {}
wheel_modules = {}

CACHE_PATH = p'$XONSH_DATA_DIR/xontrib-salt.json'


events.doc('on_salt_login', """
on_salt_login() -> None

Fires when we (re)authenticate with the salt master.
""")


def _try_load_cache():
    global exec_modules, runner_modules, wheel_modules
    if not CACHE_PATH.exists():
        return
    with CACHE_PATH.open('r') as cp:
        try:
            data = json.load(cp)
            exec_modules = data['exec']
            runner_modules = data['runner']
            wheel_modules = data['wheel']
        except Exception:
            return


def _save_cache():
    with CACHE_PATH.open('w') as cp:
        json.dump({
            'exec': exec_modules,
            'runner': runner_modules,
            'wheel': wheel_modules,
        }, cp)


def login():
    global salt_client
    salt_client = cumin.Client(auto_login=False)

    # Ok, on to the actual stuff
    try:
        auth = salt_client.login(salt_client.config['user'], salt_client.config['password'], salt_client.config['eauth'])
    except Exception:
        # Try again in 5s, probably lack of network after waking up
        schedule.delay(5).do(login)
    else:
        schedule.when(auth['expire']).do(login)
        events.on_salt_login.fire()


def _parse_docs(info):
    rv = {}
    for dotted, docstring in info.items():
        assert '.' in dotted, (dotted, docstring)
        mod, func = dotted.split('.', 1)
        rv.setdefault(mod, {})[func] = docstring
    return rv


@events.on_salt_login
def _update_modules():
    global exec_modules, runner_modules, wheel_modules
    exec_modules = _parse_docs(salt_client.runner('doc.execution'))
    runner_modules = _parse_docs(salt_client.runner('doc.runner'))
    wheel_modules = _parse_docs(salt_client.runner('doc.wheel'))
    _save_cache()


class Module(types.SimpleNamespace):
    _funcs = None
    _name = None
    _client = None

    def __getattr__(self, name):
        try:
            docstring = self._funcs[name]
        except KeyError:
            docstring = None

        def _call(*pargs, **kwargs):
            return self._rpc(self._name + '.' + name, *pargs, **kwargs)

        _call.__name__ = name
        _call.__qualname__ = 'Client.<{}.{}>'.format(self._name, name)
        _call.__doc__ = docstring

        return _call

    def __dir__(self):
        rv = super().__dir__()
        rv += list(self._funcs.keys())
        return rv

    def __repr__(self):
        attrs = vars(self).copy()
        del attrs['_funcs']
        return "{}({})".format(
            type(self).__name__,
            ', '.join("{}={!r}".format(k, v) for k, v in attrs.items())
        )


class ExecModule(Module):
    _target = None

    def _rpc(self, _name, *pargs, **kwargs):
        return self._client.local(self._target, _name, pargs, kwargs, tgt_type='compound')


class SingleExecModule(Module):
    _target = None

    def _rpc(self, _name, *pargs, **kwargs):
        rv = self._client.local(self._target, _name, pargs, kwargs, tgt_type='list')
        assert len(rv) == 1
        return rv[self._target]


class RunnerModule(Module):
    def _rpc(self, _name, *pargs, **kwargs):
        return self._client.runner(_name, pargs, **kwargs)


class WheelModule(Module):
    def _rpc(self, _name, *pargs, **kwargs):
        return self._client.wheel(_name, pargs, kwargs)['data']['return']


class MinionQuery(types.SimpleNamespace):
    _target = None
    _client = None

    def __getattr__(self, name):
        try:
            funcs = exec_modules[name]
        except KeyError:
            funcs = {}
        return ExecModule(_target=self._target, _client=self._client, _name=name, _funcs=funcs)

    def __dir__(self):
        rv = super().__dir__()
        rv += list(exec_modules.keys())
        return rv

    def __iter__(self):
        # TODO: Is there a way to do this without sending commands to minions?
        yield from self.test.ping().keys()


class Minion(types.SimpleNamespace):
    _target = None
    _client = None

    def __getattr__(self, name):
        try:
            funcs = exec_modules[name]
        except KeyError:
            funcs = {}
        return SingleExecModule(_target=self._target, _client=self._client, _name=name, _funcs=funcs)

    def __dir__(self):
        rv = super().__dir__()
        rv += list(exec_modules.keys())
        return rv


class Client(collections.abc.Mapping):
    """
    salt['minion-id'].spam.eggs() -> Manipulate a single minion
    salt('G@kernel:linux').spam.eggs() -> Manipulate a whole group of minions (by compound match)
    salt.spam.eggs() -> Manipulate the master (Runner or Wheel)

    Acts as a mapping of all joined minions.
    """

    # Minion Queries
    def __call__(self, key):
        """
        Perform a compound match of minions.
        """
        return MinionQuery(_target=key, _client=salt_client)

    # Master (Runners & Wheels)
    def __getattr__(self, name):
        if name in runner_modules:
            return RunnerModule(_client=salt_client, _name=name, _funcs=runner_modules[name])
        elif name in wheel_modules:
            return WheelModule(_client=salt_client, _name=name, _funcs=wheel_modules[name])
        else:
            raise AttributeError

    def __dir__(self):
        rv = super().__dir__()
        rv += list(set(runner_modules.keys()) | set(wheel_modules.keys()))
        return rv

    # Individual Minions
    # TODO: Minion list caching? Probably requires listening to events on a background thread.
    def __getitem__(self, name):
        """
        Get an individual minion.
        """
        return Minion(_target=name, _client=salt_client)

    def __iter__(self):
        """
        Query for the list of joined minions
        """
        yield from self.manage.joined()

    def __len__(self):
        """
        Count the number of joined minions
        """
        return len(self.manage.joined())

    def __contains__(self, name):
        """
        Check if this is a known joined minion
        """
        return name in self.manage.joined()

    # Utilities
    def events(self):
        """
        Generator tied to the Salt event bus. Produces data roughly in the form of:

            {
                'data': {
                    '_stamp': '2017-07-31T20:32:29.691100',
                    'fun': 'runner.manage.status',
                    'fun_args': [],
                    'jid': '20170731163229231910',
                    'user': 'astro73'
                },
                'tag': 'salt/run/20170731163229231910/new'
            }

        """
        yield from salt_client.events()

    def rehash(self):
        """
        Reloads some data. Run this if you've changed the master configuration.
        """
        _update_modules()


def _silence_logger(logger):
    logger.propagate = False
    logger.setLevel(999)
    logger.handlers = []


_try_load_cache()
schedule.delay(0).do(login)
salt = Client()
