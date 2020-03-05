xontrib-salt
===============================

Overview
--------

SaltStack, accessible from xonsh

Makes use of Salt's HTTP RPC via Cumin_, so make sure you've configured netapi_
and eauth_ modules. Credentials come from your pepperrc_ file.

Installation / Usage
--------------------

To install use pip:

    $ xpip install https://github.com/astronouth7303/xontrib-salt/archive/master.zip


Or clone the repo:

    $ git clone https://github.com/astronouth7303/xontrib-salt.git
    $ xpip install ./xontrib-salt

Contributing
------------

Fork, submit a pull request, and we'll have a discussion. Keep to PEP8.

Example
-------

Runner commands:

   $ salt.saltuitl.sync_all()


Standard minion commands:

   $ salt('*').test.ping()
   $ salt['myminion'].test.ping()

Credits
---------

This package was created with cookiecutter_ and the xontrib_ template.


.. _cumin: https://github.com/astronouth7303/cumin
.. _netapi: https://docs.saltstack.com/en/develop/ref/netapi/all/index.html
.. _eauth: https://docs.saltstack.com/en/latest/topics/eauth/index.html
.. _pepperrc: https://github.com/saltstack/pepper/blob/develop/README.rst#configuration
.. _cookiecutter: https://github.com/audreyr/cookiecutter
.. _xontrib: https://github.com/laerus/cookiecutter-xontrib
