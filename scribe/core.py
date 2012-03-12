#!/usr/bin/env python
import logging
import os
from   tornado.httpserver import HTTPServer
from   tornado.ioloop import IOLoop
from   tornado.web import Application

from   scribe import ScribeApplication, ScribeConnection
import settings

logger = logging.getLogger()
logger.addHandler(logging.StreamHandler())
logger.setLevel(logging.WARNING)

HTTPServer(ScribeApplication()).listen(port=settings.LISTEN_PORT)
IOLoop.instance().start()
