# FIXME re-enable gzip encoding
# TODO handle out-of-order messages (modification before adding, etc - timeout while waiting?)
import datetime
from   gridfs import GridFS
import httplib
import os
import pymongo
from   math import exp, log, pi
from   matplotlib.mlab import specgram
from   pylab import cm, figure, fromstring
from   StringIO import StringIO
from   tornadio2 import SocketConnection, TornadioRouter, event
from   tornado import gen
from   tornado.template import Loader
from   tornado.web import StaticFileHandler, Application as TornadoApplication
from   tornado.util import ObjectDict
import uuid
from   vortex import Application, Resource, parse_range_header
from   vortex.resources import DictResource, StaticFileResource
from   vortex.responses import HTTPPreamble, HTTPFoundResponse, HTTPResponse
import wave

import settings

ROOT_DIR = os.path.join(os.path.dirname(__file__), os.pardir)
STATIC_DIR = os.path.join(ROOT_DIR, 'static')

CACHE_TIME = StaticFileHandler.CACHE_MAX_AGE
PNG_HEADERS = {
    'Content-Type': 'image/png',
    'Expires': str(datetime.datetime.utcnow()+datetime.timedelta(seconds=CACHE_TIME)),
    'Cache-Control': 'max-age='+str(CACHE_TIME)
}

class AppResource(Resource):
    def __init__(self, app):
        self.app = app


class EditsResource(AppResource):
    def __getitem__(self, name):
        file = self.app.fs.get_last_version(name)
        sound = file.read()
        file.close()
        return EditResource(self.app, sound, self.app.db.info.find_one({'_id': name}))


class EditResource(AppResource, DictResource):
    def __init__(self, app, sound, info):
        AppResource.__init__(self, app)
        DictResource.__init__(self, {
            'spectrogram': SpectrogramResource(self.app, sound),
            'sound': SoundResource(self.app, sound),
            'waveform': WaveformResource(self.app, sound),
            'marks': MarksResource(self.app, info),
        })
        self.sound = sound
        self.info = info

    def get(self, request):
        self.app.db.info.update({'_id': self.info['_id']}, {'$inc': {'user_id': 1}})
        return self.app.loader.load('sound.html').generate(info=self.info)


class MarksResource(AppResource):
    def __init__(self, app, info):
        AppResource.__init__(self, app)
        self.info = info

    def __getitem__(self, name):
        return MarkResource(self.app, self.info, name)


class MarkResource(AppResource):
    def __init__(self, app, info, id):
        AppResource.__init__(self, app)
        self.info = info
        self.id = id

    def post(self, request, pos, label=''):
        return ''

    def delete(self, request):
        return ''


class SpectrogramResource(AppResource):
    def __init__(self, app, sound):
        AppResource.__init__(self, app)
        self.sound = sound

    def get(self, request, start=0, stop=-1):
        spf = wave.open(StringIO(self.sound), 'r')
        framerate = float(spf.getframerate())
        start = float(start)
        stop = float(stop)

        fig = figure()
        ax = fig.add_subplot(111, frameon=False)

        window_size = 0.005
        NFFT = 128 #framerate*window_size

        frames = fromstring(spf.readframes(-1), 'Int16')

        duration = len(frames)/spf.getnframes()*framerate

        powers, freqs, times, image = ax.specgram(
            frames,
            Fs=framerate,
            NFFT=NFFT,
            noverlap=NFFT-1,
            #window=lambda x, alpha=2.5: exp(-0.5*(alpha * linspace(-(len(x)-1)/2., (len(x)-1)/2., len(x)) /(len(x)/2.))**2.)*x,
            cmap=cm.gray_r
        )

        dyn_range = 70
        preemph_start = 50
        preemph_boost = 6

        max_frame = -200
        c = log(2, 10)
        #for f in range(len(powers)):
        #    for t in range(len(powers[f])):
        #        power = powers[f][t]
        #        powers[f][t] = 10*log(abs(power), 10)+(log(freqs[f]/preemph_start, 2)*preemph_boost if freqs[f] >= preemph_start else 0) if power != 0 else -200
        #        max_frame = max(max_frame, powers[f][t])

        #max_frame = 100
        #for f in range(len(powers)):
        #    for t in range(len(powers[f])):
        #        powers[f][t] = 1.0-(max_frame-powers[f][t])/dyn_range if powers[f][t] > max_frame-dyn_range else 0

        #ax.imshow(powers, origin='lower', aspect='auto', cmap=cm.gray_r)

        ax.set_xlim(start, stop if stop != -1 else spf.getnframes()/framerate)
        ax.set_xticks([])
        ax.set_yticks([])
        fig.subplots_adjust(left=0, right=1, bottom=0, top=1, wspace=0, hspace=0)
        fig.set_size_inches(1.78, 0.5)

        output = StringIO()
        fig.savefig(output, format='png', dpi=600)
        spf.close()

        return HTTPResponse(HTTPPreamble(headers=PNG_HEADERS.copy()), body=output.getvalue())


class WaveformResource(AppResource):
    def __init__(self, app, sound):
        AppResource.__init__(self, app)
        self.sound = sound

    def get(self, request, start=0, stop=-1):
        spf = wave.open(StringIO(self.sound), 'r')
        framerate = spf.getframerate()
        start = float(start)
        stop = float(stop)

        fig = figure()
        ax = fig.add_subplot(111, frameon=False)

        ax.set_xticks([])
        ax.set_yticks([])
        ax.set_xlim(start*framerate, stop*framerate if stop != -1 else spf.getnframes())
        ax.plot(fromstring(spf.readframes(-1), 'Int16'), color='black')
        fig.subplots_adjust(left=0, right=1, bottom=0, top=1, hspace=0)
        #fig.set_size_inches(1.78, 0.5)

        output = StringIO()
        fig.savefig(output, format='png')
        spf.close()

        return HTTPResponse(HTTPPreamble(headers=PNG_HEADERS.copy()), body=output.getvalue())


class SoundResource(AppResource):
    def __init__(self, app, sound):
        AppResource.__init__(self, app)
        self.sound = sound

    def get(self, request):
        status_code = httplib.OK
        headers = {
            'Accept-Range': 'bytes',
            'Content-Type': 'audio/wav'
        }
        sound = self.sound
        request_range = request.headers.get('Range')
        file_size = len(self.sound)
        body_range = parse_range_header(request_range, file_size)
        if request_range is not None:
            status_code = httplib.PARTIAL_CONTENT
            headers['Content-Range'] = 'bytes %i-%i/%i' % (body_range[0], body_range[1], file_size)
            sound = self.sound[body_range[0]:body_range[1]]
        return HTTPResponse(HTTPPreamble(status_code=status_code, headers=headers), body=sound)


class HomeResource(AppResource):
    def get(self, request):
        return self.app.loader.load('home.html').generate()

    def post(self, request):
        """Upload the user's sound and redirect to transcription page."""
        session_id = uuid.uuid4().hex
        body = request.files['sound'][0].body
        self.app.fs.put(body, filename=session_id)
        spf = wave.open(StringIO(body), 'r')
        self.app.db.info.insert({'_id': session_id, 'duration': float(spf.getnframes())/spf.getframerate(), 'marks': [], 'user_id': 0, 'mark_counter': 0})
        spf.close()
        return HTTPFoundResponse(location='/sounds/'+session_id)


class ScribeApplication(Application):
    def __init__(self):
        self.db = pymongo.Connection(port=settings.DB_PORT)[settings.DB_NAME]
        self.fs = GridFS(self.db)
        self.loader = Loader(
            os.path.join(ROOT_DIR, 'template'),
            autoescape=None,
            namespace={
                'static_url': lambda url: StaticFileHandler.make_static_url({'static_path': STATIC_DIR}, url),
                '_modules': ObjectDict({'Template': lambda template, **kwargs: self.loader.load(template).generate(**kwargs)}),
            },
        )

        router = TornadioRouter(ScribeConnection)
        router.app = self
        socketio = TornadoApplication(router.urls, app=self)
        self.connections = []

        class FooResource(Resource):
            def __call__(self, request):
                socketio(request)

            def __getitem__(self, name):
                return self

        Application.__init__(self, {
            '': HomeResource(self),
            'favicon.ico': StaticFileResource(os.path.join(STATIC_DIR, 'img', 'favicon.ico')),
            'sounds': EditsResource(self),
            'static': StaticFileResource(STATIC_DIR),
            'socket.io': FooResource(),
        })


class ScribeConnection(SocketConnection):
    def __init__(self, session, endpoint=None):
        SocketConnection.__init__(self, session, endpoint)
        self.app = session.server.app

    def on_open(self, request):
        self.app.connections.append(self)

    def on_close(self):
        self.app.connections.remove(self)

    def broadcast(self, name, **kwargs):
        for connection in self.app.connections:
            if connection != self:
                connection.emit(name, **kwargs)

    @event
    def add_mark(self, sound, id, pos, label):
        query = {'_id': sound, 'marks.id': id}
        mark = {'id': id, 'pos': pos, 'label': label}
        if self.app.db.info.find_one(query) is not None:
            update = {'$set': {'marks.$': mark}}
        else:
            del query['marks.id']
            update = {'$push': {'marks': mark}, '$inc': {'mark_counter': 1}}
        self.app.db.info.update(query, update)
        self.broadcast('add_mark', id=id, pos=pos, label=label)

    @event
    def delete_mark(self, sound, id):
        self.app.db.info.update({'_id': sound}, {'$pull': {'marks': {'id': id}}})
        self.broadcast('delete_mark', id=id)

    @event
    def send_message(self, sender, message):
        self.broadcast('receive_message', sender=sender, message=message)
