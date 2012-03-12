LISTEN_PORT = 8081

DB_PORT = 27017
DB_NAME = 'scribe'

try:
    from local_settings import *
except ImportError:
    pass
