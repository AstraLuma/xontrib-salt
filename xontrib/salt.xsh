xontrib load schedule
import types
import pepper
import pepper.cli

__all__ = 'salt',
__version__ = '0.0.1'


salt_client = None


def _salt_login():
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
    auth = salt_client.login(*pc.parse_login())
    schedule.when(auth['expire']).do(_salt_login)


class SaltCommand(types.SimpleNamespace):
    command = None
    target = None

    def __getattr__(self, name):
        if self.command:
            return SaltCommand(target=self.target, command=self.command + '.' + name)
        else:
            return SaltCommand(target=self.target, command=name)

    def __call__(self, *pargs, **kwargs):
        if self.target:
            rv = salt_client.local(self.target, self.command, pargs, kwargs, expr_form='compound')
        else:
            rv = salt_client.runner(self.command, pargs, **kwargs)

        if 'return' in rv:
            rv = rv['return'][0]

        return rv


class SaltClient:
    def __getitem__(self, key):
        return SaltCommand(target=key)

    def __getattr__(self, name):
        return SaltCommand(command=name)


_salt_login()
salt = SaltClient()
