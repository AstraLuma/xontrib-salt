xontrib load schedule
import types
try:
    import ujson as json
except ImportError:
    import json
import pepper
import pepper.cli
import logging

__all__ = 'salt',
__version__ = '0.0.1'


salt_client = None

exec_modules = None
runner_modules = None
wheel_modules = None

CACHE_PATH = p'$XONSH_DATA_DIR/xontrib-salt.json'


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
    # We do this to be able to parse .pepperrc
    pc = pepper.cli.PepperCli()
    pc.parse()
    salt_client = pepper.Pepper(
        pc.parse_url(),
        debug_http=pc.options.debug_http,
        ignore_ssl_errors=pc.options.ignore_ssl_certificate_errors
    )

    # Ok, on to the actual stuff
    try:
        auth = salt_client.login(*pc.parse_login())
    except Exception:
        # Try again in 5s, probably lack of network after waking up
        schedule.delay(5).do(login)
    else:
        schedule.when(auth['expire']).do(login)
        if exec_modules is None:
            _update_modules()
        else:
            schedule.delay(0).do(_update_modules)


def _parse_docs(info):
    rv = {}
    for dotted, docstring in info.items():
        assert '.' in dotted, (dotted, docstring)
        mod, func = dotted.split('.', 1)
        rv.setdefault(mod, {})[func] = docstring
    return rv


def _update_modules():
    global exec_modules, runner_modules, wheel_modules
    # FIXME: Cache this information in the filesystem
    exec_modules = _parse_docs(salt_client.runner('doc.execution')['return'][0])
    runner_modules = _parse_docs(salt_client.runner('doc.runner')['return'][0])
    wheel_modules = _parse_docs(salt_client.runner('doc.wheel')['return'][0])
    _save_cache()


class Module(types.SimpleNamespace):
    _funcs = None
    _name = None
    _client = None

    def __getattr__(self, name):
        try:
            docstring = self._funcs[name]
        except KeyError:
            raise AttributeError

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
        return self._client.local(self._target, _name, pargs, kwargs, expr_form='compound')['return'][0]


class RunnerModule(Module):
    def _rpc(self, _name, *pargs, **kwargs):
        return self._client.runner(_name, pargs, **kwargs)['return'][0]


class WheelModule(Module):
    def _rpc(self, _name, *pargs, **kwargs):
        return self._client.wheel(_name, pargs, kwargs)['return'][0]['data']['return']


class MinionQuery(types.SimpleNamespace):
    _target = None
    _client = None

    def __getattr__(self, name):
        try:
            funcs = exec_modules[name]
        except KeyError:
            raise AttributeError
        return ExecModule(_target=self._target, _client=self._client, _name=name, _funcs=funcs)

    def __dir__(self):
        rv = super().__dir__()
        rv += list(exec_modules.keys())
        return rv


class Client:
    def __getitem__(self, key):
        return MinionQuery(_target=key, _client=salt_client)

    def __getattr__(self, name):
        if name in runner_modules:
            return RunnerModule(_client=salt_client, _name=name, _funcs=runner_modules[name])
        elif name in wheel_modules:
            return WheelModule(_client=salt_client, _name=name, _funcs=wheel_modules[name])
        else:
            raise AttributeError

    def __dir__(self):
        rv = super().__dir__()
        rv += list(set(runner_modules.keys()) | set(wheel_modules))
        return rv

    def events(self):
        import requests
        import json
        headers = {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'X-Auth-Token': salt_client.auth['token']
        }
        with requests.get(salt_client._construct_url('/events'), headers=headers, verify=False, stream=True) as resp:
            for line in resp.iter_lines():
                line = line.decode('utf-8')
                if line.startswith('data:'):
                    line = line[len('data:'):]
                    data = json.loads(line.strip())
                    yield data


def _silence_logger(logger):
    logger.propagate = False
    logger.setLevel(999)
    # Can't actually enumerate loggers to remove them


# libpepper throws exceptions AND logs. Completely unnecessary.
_silence_logger(logging.getLogger('pepper'))

_try_load_cache()
login()
salt = Client()
