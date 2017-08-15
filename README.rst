xontrib-salt
===============================

Overview
--------

SaltStack, accessible from xonsh

Makes use of Salt's HTTP RPC via Pepper, so make sure you've configured netapi_
and eauth_ modules. Credentials come from your pepperrc_ file.

Installation / Usage
--------------------

To install use pip:

    $ xip install xontrib-salt


Or clone the repo:

    $ git clone https://github.com/astronouth7303/xontrib-salt.git
    $ xip install ./xontrib-salt

Contributing
------------

Fork, submit a pull request, and we'll have a discussion. Keep to PEP8.

Example
-------

Runner commands:

   $ salt.saltuitl.sync_all()


Standard minion commands:

   $ salt['*'].test.ping()

Credits
---------

This package was created with cookiecutter_ and the xontrib_ template.


.. _netapi: https://docs.saltstack.com/en/develop/ref/netapi/all/index.html
.. _eauth: https://docs.saltstack.com/en/latest/topics/eauth/index.html
.. _pepperrc: https://github.com/saltstack/pepper/blob/develop/README.rst#configuration
.. _cookiecutter: https://github.com/audreyr/cookiecutter
.. _xontrib: https://github.com/laerus/cookiecutter-xontrib
