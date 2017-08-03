xontrib load schedule
import types
try:
    import ujson as json
except ImportError:
    import json
import pepper
import pepper.cli
import logging
import requests
import time

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


def _stream_raw_sse(*pargs, _last_event_id=None, headers=None, **kwargs):
    """
    Streams Server-Sent Events, each event produced as a sequence of
    (field, value) pairs.

    Does not handle reconnection, etc.
    """
    if headers is None:
        headers = {}
    headers['Accept'] = 'text/event-stream'
    headers['Cache-Control'] = 'no-cache'
    # Per https://html.spec.whatwg.org/multipage/server-sent-events.html#sse-processing-model
    if _last_event_id is not None:
        headers['Last-Event-ID'] = _last_event_id

    with requests.get(*pargs, headers=headers, stream=True, **kwargs) as resp:
        fields = []
        for line in resp.iter_lines(decode_unicode=True):
            # https://html.spec.whatwg.org/multipage/server-sent-events.html#event-stream-interpretation
            if not line:
                yield fields
                fields = []
            elif line.startswith(':'):
                pass
            elif ':' in line:
                field, value = line.split(':', 1)
                if value.startswith(' '):
                    value = value[1:]
                fields += [(field, value)]
            else:  # Non-blank, without a colon
                fields += [(line, '')]


def _stream_sse(*pargs, **kwargs):
    """
    Streams server-sent events, producing a dictionary of the fields.

    Handles reconnecting, Last-Event-ID, and retry waits.

    Deviates by spec by passing through unknown fields instead of ignoring them.
    If an unknown field is given more than once, the last given wins (like
    event and id).
    """
    retry = 0
    last_id = None
    while True:
        try:
            for rawmsg in _stream_raw_sse(*pargs, _last_event_id=last_id, **kwargs):
                msg = {'event': 'message', 'data': ''}
                # https://html.spec.whatwg.org/multipage/server-sent-events.html#event-stream-interpretation
                for k, v in rawmsg:
                    if k == 'retry':
                        try:
                            retry = int(v)
                        except ValueError:
                            pass
                    elif k == 'data':
                        if msg['data']:
                            msg['data'] += '\n' + v
                        else:
                            msg['data'] = v
                    else:
                        if k == 'id':
                            last_id = v
                        # Spec says we should ignore unknown fields. We're passing them on.
                        msg[k] = v
                if not msg['data']:
                    pass
                yield msg
            else:
                raise StopIteration  # Really just exists to get caught in the next line
        except (StopIteration, requests.RequestException, EOFError):
            # End of stream, try to reconnect
            # NOTE: GeneratorExit is thrown if the consumer kills us (or we get GC'd)
            # TODO: Log something?

            # Wait, fall through, and start at the top
            time.sleep(retry / 1000)


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
        import requests
        import json
        # This is ripped from pepper, and doesn't support kerb to boot
        headers = {
            'X-Auth-Token': salt_client.auth['token']
        }
        for msg in _stream_sse(
            salt_client._construct_url('/events'),
            headers=headers,
            verify=False,
        ):
            data = json.loads(msg['data'])
            yield data

    def rehash(self):
        """
        Reloads some data. Run this if you've changed the master configuration.
        """
        _update_modules()


def _silence_logger(logger):
    logger.propagate = False
    logger.setLevel(999)
    # Can't actually enumerate loggers to remove them


# libpepper throws exceptions AND logs. Completely unnecessary.
_silence_logger(logging.getLogger('pepper'))

_try_load_cache()
login()
salt = Client()
