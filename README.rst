xontrib-salt
===============================

version number: 0.0.1
author: Jamie Bliss

Overview
--------

SaltStack, accessible from xonsh

Makes use of Salt's HTTP RPC via Pepper, so make sure you've configured a `netapi module`_.
Credentials come from your .pepperrc_ file.

Installation / Usage
--------------------

To install use pip:

    $ pip install xontrib-salt


Or clone the repo:

    $ git clone https://github.com/astronouth7303/xontrib-salt.git
    $ pip install ./xontrib-salt

Contributing
------------

Fork, submit a pull request, and we'll have a discussion. Keep to PEP8.

Example
-------

   $ salt.saltuitl.sync_all()

   $ salt['*'].test.ping()

Credits
---------

This package was created with cookiecutter_ and the xontrib_ template.


.. _`netapi module`: https://docs.saltstack.com/en/develop/ref/netapi/all/index.html
.. _.pepperrc: https://github.com/saltstack/pepper/blob/develop/README.rst#configuration
.. _cookiecutter: https://github.com/audreyr/cookiecutter
.. _xontrib: https://github.com/laerus/cookiecutter-xontrib
