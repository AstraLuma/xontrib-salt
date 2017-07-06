xontrib load schedule
import types
import pepper
import pepper.cli

__all__ = 'salt',
__version__ = '0.0.1'


salt_client = None

exec_modules = None
runner_modules = None
wheel_modules = None


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
        _update_modules()


def _parse_docs(info):
    rv = {}
    for dotted, docstring in info.items():
        assert '.' in dotted, (dotted, docstring)
        mod, func = dotted.split('.', 1)
        rv.setdefault(mod, {})[func] = docstring
    return rv


def _update_modules():
    global exec_modules, runner_modules, wheel_modules
    if exec_modules is None:
        print("Loading salt information...")
    # FIXME: Cache this information in the filesystem
    exec_modules = _parse_docs(salt_client.runner('doc.execution')['return'][0])
    runner_modules = _parse_docs(salt_client.runner('doc.runner')['return'][0])
    wheel_modules = _parse_docs(salt_client.runner('doc.wheel')['return'][0])


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
            rv = self._rpc(self._name + '.' + name, *pargs, **kwargs)
            if 'return' in rv:
                rv = rv['return'][0]
            return rv

        _call.__name__ = name
        _call.__qualname__ = 'salt.{}.{}'.format(self._name, name)
        _call.__doc__ = docstring

        return _call

    def __dir__(self):
        rv = super().__dir__()
        rv += list(self._funcs.keys())
        return rv


class ExecModule(Module):
    _target = None

    def _rpc(self, name, *pargs, **kwargs):
        return self._client.local(self._target, name, pargs, kwargs, expr_form='compound')


class RunnerModule(Module):
    def _rpc(self, name, *pargs, **kwargs):
        return self._client.runner(name, pargs, **kwargs)


class WheelModule(Module):
    def _rpc(self, name, *pargs, **kwargs):
        return self._client.wheel(name, pargs, kwargs)


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
            return RunnerModule(_client=salt_client, _name=name, _funcs=wheel_modules[name])
        else:
            raise AttributeError

    def __dir__(self):
        rv = super().__dir__()
        rv += list(set(runner_modules.keys()) | set(wheel_modules))
        return rv


login()
salt = Client()
