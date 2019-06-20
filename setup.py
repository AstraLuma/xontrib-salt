from setuptools import setup

setup(
    name='xontrib-salt',
    version='0.0.1',
    url='https://github.com/astronouth7303/xontrib-salt',
    license='MIT',
    author='Jamie Bliss',
    author_email='jamie@ivyleav.es',
    description='SaltStack, accessible from xonsh',
    packages=['xontrib'],
    install_requires=['salt-cumin', 'xontrib-schedule'],
    package_dir={'xontrib': 'xontrib'},
    package_data={'xontrib': ['*.xsh']},
    platforms='any',
)
