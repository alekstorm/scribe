url = document.location.href

SLIDER_HEIGHT = 80
WAVEFORM_HEIGHT = 160
GRAPH_HEIGHT = SLIDER_HEIGHT+WAVEFORM_HEIGHT*2

SLIDER_HANDLE_RADIUS = 10
SLIDER_SIDE_WIDTH = 10

LINE_COLOR = Graphics.getRGB(0,0,255)
LINE_HEIGHT = WAVEFORM_HEIGHT*2
MARK_LINE_COLOR = Graphics.getRGB(0,255,0)
MARK_LINE_HOVER_COLOR = Graphics.getRGB(255,127,0)
PLAY_FADE_WIDTH = 100

ZOOM_IN_SCALE = 0.25

zoom_start = null
zoom_stop = null
canvas_scale = null
canvas_offset = null
selection = [0]

# TODO only one stage.update() for each event firing
# TODO replace WidgetLine with Widget

socket = new io.connect('http://'+window.location.host)
socket.on('disconnect', -> socket.socket.reconnect())

sound = new buzz.sound("#{url}/sound", {preload: true})

DisplayObject::bind = (type, handler) ->
    @bound ||= {}
    @bound[type] ||= []
    @bound[type].push(handler)

DisplayObject::unbind = (type, handler) ->
    @bound ||= {}
    @bound[type] ||= []
    index = $.inArray(handler, @bound[type])
    if index != -1
        @bound[type].splice(index, 1)

DisplayObject::trigger = (type, event) ->
    @bound ||= {}
    for handler in @bound[type] or []
        handler.call(this, event)


class Transcribe extends Stage
    constructor: (canvas, @base_stage) ->
        @initialize(canvas)

    initialize: (canvas) ->
        Stage.prototype.initialize.call(this, canvas)
        @zoom = new Zoom(this, @base_stage)
        @addChild(@zoom)

        @horiz_cursor_line = new HorizCursorLine(this)
        @addChild(@horiz_cursor_line)
        @vert_cursor_line = new VertCursorLine(this)
        @addChild(@vert_cursor_line)

        @slider = new Slider(this)
        @addChild(@slider)

        @mark_collection = new MarkCollection(this)
        @addChild(@mark_collection)

        $canvas = $(canvas)
        @cursors = []
        @add_cursor(this, 0, new Rectangle(0, 0, $canvas.width(), $canvas.height()), 'crosshair')
        $canvas.mousemove (event) =>
           for cursor in @cursors
               if cursor.rect.x <= event.pageX-$canvas.offset().left < cursor.rect.x+cursor.rect.width and cursor.rect.y <= event.pageY-$canvas.offset().top < cursor.rect.y+cursor.rect.height
                   $canvas.css('cursor', cursor.display)
                   break

    add_cursor: (key, z, rect, display) ->
        cursor = {key: key, z: z, rect: rect, display: display}
        for i in [0...@cursors.length]
            if @cursors[i].z <= z
                @cursors.splice(i, 0, cursor)
                return
        @cursors.push(cursor)

    modify_cursor: (key, rect, display=null) ->
        for cursor in @cursors
            if cursor.key == key
                cursor.rect = rect
                if display != null
                    cursor.display = display
                return

    remove_cursor: (key) ->
        for i in [0...@cursors.length]
            if @cursors.key == key
                @cursors.splice(i, 1)
                return


class HorizCursorLine extends Shape
    constructor: (@stage) ->
        @initialize()

    initialize: ->
        g = new Graphics().setStrokeStyle(1).beginStroke(LINE_COLOR)
        i = 0
        while i <= LINE_HEIGHT
            g.moveTo(0.5, i)
            i += 4
            g.lineTo(0.5, i)
            i += 6

        Shape.prototype.initialize.call(this, g)
        @cache(0, 0, 2, LINE_HEIGHT)
        @y = SLIDER_HEIGHT
        @visible = false
        canvas = $(@stage.canvas)

        canvas.mouseout (event) =>
            @visible = false
            @stage.update()

        canvas.mousemove (event) =>
            stageX = event.pageX-canvas.offset().left
            stageY = event.pageY-canvas.offset().top
            @visible = false
            if SLIDER_HEIGHT < stageY < GRAPH_HEIGHT
                @visible = true
                @x = stageX
            @stage.update()


class VertCursorLine extends Shape
    constructor: (@stage) ->
        @initialize()

    initialize: ->
        g = new Graphics().setStrokeStyle(1).beginStroke(LINE_COLOR)
        i = 0
        canvas = $(@stage.canvas)
        while i <= canvas.width()
            g.moveTo(i, 0.5)
            i += 4
            g.lineTo(i, 0.5)
            i += 6

        Shape.prototype.initialize.call(this, g)
        @cache(0, 0, canvas.width(), 2)
        @visible = false

        canvas.mouseout (event) =>
            @visible = false
            @stage.update()

        canvas.mousemove (event) =>
            stageY = event.pageY-canvas.offset().top
            @visible = false
            if SLIDER_HEIGHT < stageY < GRAPH_HEIGHT
                @visible = true
                @y = stageY
            @stage.update()


class DragLine extends Shape
    constructor: (@stage) ->
        @initialize()

    initialize: ->
        Shape.prototype.initialize.call(this, new Graphics()
            .setStrokeStyle(1)
            .beginStroke(LINE_COLOR)
            .moveTo(0.5, 0)
            .lineTo(0.5, WAVEFORM_HEIGHT*2)
        )
        @cache(0, 0, 2, WAVEFORM_HEIGHT*2)
        @visible = false

    move: (x) ->
        @visible = true
        @x = x
        @stage.update()


class WidgetLine extends Shape
    constructor: (@stage, stack_offset, color) ->
        @initialize(stack_offset, color)

    initialize: (stack_offset, color) ->
        Shape.prototype.initialize.call(this, new Graphics()
            .setStrokeStyle(1)
            .beginStroke(color)
            .moveTo(0.5, 0)
            .lineTo(0.5, WAVEFORM_HEIGHT*2+stack_offset)
        )
        @cache(0, 0, 2, WAVEFORM_HEIGHT*2)


class PlayLine extends Shape
    constructor: (@stage) ->
        @initialize()

    initialize: ->
        Shape.prototype.initialize.call(this, new Graphics()
            .beginLinearGradientFill([Graphics.getRGB(255,0,0,0), Graphics.getRGB(255,0,0,0.8)], [0,1], 0, LINE_HEIGHT/2, PLAY_FADE_WIDTH, LINE_HEIGHT/2)
            .drawRect(0, 0, PLAY_FADE_WIDTH, LINE_HEIGHT)
        )
        @cache(0, 0, PLAY_FADE_WIDTH, LINE_HEIGHT)


class SelectionRect extends Shape
    constructor: (@stage, x, width) ->
        @initialize(x, width)

    initialize: (x, width) ->
        Shape.prototype.initialize.call(this, new Graphics()
            .beginFill(Graphics.getRGB(0,0,255,0.3))
            .rect(x, 0, width, WAVEFORM_HEIGHT*2)
        )


class Zoom extends Container
    constructor: (@stage, @base_stage) ->
        @initialize()

    initialize: ->
        Container.prototype.initialize.call(this)
        @canvas = $(@stage.canvas)
        @waveform = new Shape(new Graphics())
        @waveform.y = SLIDER_HEIGHT
        @y = SLIDER_HEIGHT
        @base_stage.addChild(@waveform)
        @spectrogram = new Shape(new Graphics())
        @base_stage.addChild(@spectrogram)
        @spectrogram.y = SLIDER_HEIGHT+WAVEFORM_HEIGHT

        @loading_counter = 0
        @waveform_image_loaded = false
        @spectrogram_image_loaded = false

        @play_line = new PlayLine()
        @play_line.visible = false
        @addChild(@play_line)

        @move(0, sound_info.duration)

        @canvas.mousedown (down_event) =>
            down_stageX = down_event.pageX-@canvas.offset().left
            stageY = down_event.pageY-@canvas.offset().top
            if SLIDER_HEIGHT < stageY < GRAPH_HEIGHT and not @stage.mark_collection.hit_widget(down_stageX, stageY)?
                drag_line = new DragLine(@stage)
                @addChild(drag_line)
                if @drag_rect?
                    @removeChild(@drag_rect)
                @drag_rect = null
                move_handler = (move_event) =>
                    stageX = move_event.pageX-@canvas.offset().left
                    drag_line.move(stageX)
                    if @drag_rect?
                        @removeChild(@drag_rect)
                    @drag_rect = new SelectionRect(@stage, down_stageX, stageX-down_stageX)
                    @addChild(@drag_rect)
                up_handler = (up_event) =>
                    stageX = up_event.pageX-@canvas.offset().left
                    cur_scale = (zoom_stop - zoom_start)/@canvas.width()
                    if up_event.pageX != down_event.pageX
                        selection = [down_stageX*cur_scale+zoom_start, stageX*cur_scale+zoom_start]
                        selection.sort()
                    else
                        selection = [stageX*cur_scale+zoom_start]
                        mark =
                            pos: selection[0]
                            label: ''
                            id: "#{sound_info.user_id}_#{sound_info.mark_counter++}"
                        save_mark(mark)
                        sync_mark(mark)
                        @stage.mark_collection.move_widgets()
                        for widget in @stage.mark_collection.widgets
                            if widget.mark.id == mark.id
                                widget.label.children('span').focus()
                    @removeChild(drag_line)
                    @canvas.unbind('mouseup', up_handler)
                    @canvas.unbind('mousemove', move_handler)
                @canvas.mousemove(move_handler)
                @canvas.mouseup(up_handler)

        $(document).keydown (event) =>
            if event.which == 9 # tab
                if sound.isPaused() or sound.isEnded() # TODO bug in buzz
                    if selection.length == 2
                        @play(selection[0], selection[1])
                    else
                        @play(zoom_start, zoom_stop)
                else
                    sound.stop()
                return false
            if event.which == 32 # spacebar
                if selection.length == 2
                    @removeChild(@drag_rect)
                    @drag_rect = null
                    @move(selection[0], selection[1])
                else
                    zoom_size = (zoom_stop - zoom_start)*ZOOM_IN_SCALE
                    @move(Math.max(0, zoom_start+zoom_size), Math.min(sound_info.duration, zoom_stop-zoom_size))
                selection = [zoom_start]
                return false

    play: (start, stop) ->
        update_play_line = =>
            if not sound.isPaused() and not sound.isEnded()
                @play_line.x = (sound.getTime()-zoom_start)/(zoom_stop-zoom_start)*@canvas.width() - PLAY_FADE_WIDTH
                setTimeout(update_play_line, 10)
            else
                @play_line.visible = false
            if sound.getTime() >= stop
                sound.stop()
            @stage.update()
        @play_line.visible = true
        sound.setTime(start)
        sound.play()
        update_play_line()

    move: (start, stop) ->
        cur_counter = ++@loading_counter
        load = =>
            if @waveform_image_loaded and @spectrogram_image_loaded
                @waveform_image_loaded = false
                @spectrogram_image_loaded = false
                zoom_start = Math.min(start, stop)
                zoom_stop = Math.max(start, stop)

                if @drag_rect?
                    @removeChild(@drag_rect)
                    x = (selection[0]-zoom_start)/(zoom_stop-zoom_start)*@canvas.width()
                    @drag_rect = new SelectionRect(@stage, x, (selection[1]-zoom_start)/(zoom_stop-zoom_start)*@canvas.width()-x)
                    @addChild(@drag_rect)
                @trigger('move')

                @waveform.graphics.drawImage(waveform_image, 0, 0, @canvas.width(), WAVEFORM_HEIGHT)
                @spectrogram.graphics.drawImage(spectrogram_image, 0, 0, @canvas.width(), WAVEFORM_HEIGHT)
                @stage.update()
                @base_stage.update()

        waveform_image = new Image()
        waveform_image.onload = =>
            if @loading_counter == cur_counter
                @waveform_image_loaded = true
                load()

        spectrogram_image = new Image()
        spectrogram_image.onload = =>
            if @loading_counter == cur_counter
                @spectrogram_image_loaded = true
                load()

        params = $.param({start: start, stop: stop})
        waveform_image.src = "#{url}/waveform?#{params}"
        spectrogram_image.src = "#{url}/spectrogram?#{params}"


class MarkCollection extends Container
    constructor: (@stage) ->
        @initialize()

    initialize: ->
        Container.prototype.initialize.call(this)
        @widgets = []
        @stage.zoom.bind('move', => @move_widgets())
        @y = SLIDER_HEIGHT

        socket.on 'add_mark', (mark) =>
            save_mark(mark)
            @move_widgets()

        socket.on 'delete_mark', (mark) =>
            delete_mark(mark.id)
            for widget in @widget
                if widget.mark.id == mark.id
                    erase_mark(widget)
                    return @move_widgets()

    update_widget: (widget) ->
        mark =
            id: widget.mark.id
            pos: widget.mark.pos
            label: widget.label.children('span').text()
        save_mark(mark)
        sync_mark(mark)

    hide_widget: (widget) ->
        widget.label.remove()
        @removeChild(widget.line)
        @stage.update()
        @widgets.splice(@widgets.indexOf(widget), 1)

    hit_widget: (stageX, stageY) ->
        for widget in @widgets
            if widget.line.x-3 <= stageX <= widget.line.x+3 and SLIDER_HEIGHT < stageY < GRAPH_HEIGHT
                return widget

    move_widgets: ->
        while @widgets.length > 0
            @hide_widget(@widgets[0])
        last_height = 0
        last_widget = null
        sound_info.marks.sort((a,b) -> b.pos - a.pos)
        canvas = $(@stage.canvas)
        for mark in sound_info.marks
            do (mark) =>
                if zoom_start < mark.pos < zoom_stop
                    left_offset = (mark.pos-zoom_start)/(zoom_stop-zoom_start)*canvas.width()
                    input = $('<span contenteditable="true">')
                        .text(mark.label)
                        .keypress((event) =>
                            event.stopPropagation()
                            if event.which == 13
                                input.blur()
                                return false
                        ).blur(=>
                            @update_widget(widget)
                            input.parent().removeClass('focus')
                        ).focus(=>
                            input.parent().addClass('focus')
                        )
                    delete_img = $('<img src="/static/img/delete.png">')
                        .click =>
                            delete_mark(mark.id)
                            @hide_widget(widget)
                            @move_widgets()
                            socket.emit('delete_mark', {sound: sound_info._id, id: mark.id})
                    label = $('<div>')
                        .addClass('label')
                        .append(input)
                        .append(delete_img)
                        .appendTo(container)
                        .css(
                            left: (canvas_offset.left+left_offset)+'px'
                            top: (canvas_offset.top+GRAPH_HEIGHT)+'px'
                        )
                    widget = {label: label, mark: mark}
                    @widgets.push(widget)

                    offset = widget.label.offset()
                    if last_widget? and offset.left+widget.label.width() >= last_widget.label.offset().left
                        stack_offset = (++last_height)*widget.label.height()
                    else
                        last_height = 0
                        stack_offset = 0

                    widget.label.offset(
                        left: offset.left
                        top: offset.top+stack_offset
                    )

                    widget.line = new WidgetLine(@stage, stack_offset, Graphics.getRGB(0,255,0))
                    widget.line.x = left_offset
                    @addChild(widget.line)

                    last_widget = widget
        @stage.update()


class Slider extends Container
    constructor: (@stage) ->
        @initialize()

    initialize: ->
        Container.prototype.initialize.call(this)
        canvas = $(@stage.canvas)
        @slider_image = new Image()
        @slider_image.onload = =>
            @addChild(new Shape(new Graphics()
                .drawImage(@slider_image, 0, 0, canvas.width(), SLIDER_HEIGHT)))
            @move(0, sound_info.duration)
            @stage.update()
        @slider_image.src = "#{url}/waveform?"+$.param({start: 0, stop: sound_info.duration})

        down_handler = (down_event) =>
            down_stageX = down_event.pageX-canvas.offset().left
            down_stageY = down_event.pageY-canvas.offset().top
            if @slider_handle and hit_mouse(@slider_handle, down_stageX, down_stageY)
                resize_left = null
                # TODO for clicking non-handle place in slider
                #new_zoom = constrain_zoom((event.stageX-slider_handle.x)*canvas_scale)
                drag_start = @slider_handle.x
                #update_slider(new_zoom[0], new_zoom[1])
                move_handler = (move_event) =>
                    @move.apply(this, constrain_zoom((move_event.pageX-canvas.offset().left-drag_start)*canvas_scale))
                up_handler = (up_event) =>
                    @stage.zoom.move.apply(@stage.zoom, constrain_zoom((up_event.pageX-canvas.offset().left-drag_start)*canvas_scale))
                    $(document).unbind('mouseup', up_handler)
                    canvas.unbind('mousemove', move_handler)
                $(document).mouseup(up_handler)
                canvas.mousemove(move_handler)
            else if @slider_handle and zoom_start/canvas_scale-SLIDER_SIDE_WIDTH <= down_stageX <= zoom_start/canvas_scale+SLIDER_SIDE_WIDTH
                resize_left = true
            else if @slider_handle and zoom_stop/canvas_scale-SLIDER_SIDE_WIDTH <= down_stageX <= zoom_stop/canvas_scale+SLIDER_SIDE_WIDTH
                resize_left = false
            if resize_left?
                start = zoom_start
                stop = zoom_stop
                move_handler = (move_event) =>
                    diff = (move_event.pageX-down_event.pageX) * (if resize_left then 1 else -1)
                    start = Math.max(0, (zoom_start/canvas_scale+diff)*canvas_scale)
                    stop = Math.min(sound_info.duration, (zoom_stop/canvas_scale-diff)*canvas_scale)
                    @move(start, stop)
                up_handler = (up_event) =>
                    @stage.zoom.move(start, stop)
                    $(document).unbind('mouseup', up_handler)
                    canvas.unbind('mousemove', move_handler)
                $(document).mouseup(up_handler)
                canvas.mousemove(move_handler)

        canvas.mousedown(down_handler)

        @stage.zoom.bind 'move', =>
            @move(zoom_start, zoom_stop)

    move: (start, stop) ->
        if @slider_box?
            @removeChild(@slider_box)
        slider_width = (stop-start)/canvas_scale
        slider_height = SLIDER_HEIGHT-4
        @slider_box = new Shape(new Graphics()
            .setStrokeStyle(3)
            .beginStroke(Graphics.getRGB(0,0,255))
            .rect(0, 0, slider_width, slider_height)
        )
        @addChild(@slider_box)
        @slider_box.x = start/canvas_scale
        @slider_box.y = 2
        if @slider_handle?
            @removeChild(@slider_handle)
            old_handle = true
        @slider_handle = new Shape(new Graphics()
            .beginFill(Graphics.getRGB(0,0,255))
            .drawCircle(0,0,SLIDER_HANDLE_RADIUS)
        )
        @addChild(@slider_handle)
        @slider_handle.x = ((stop-start)/2+start)/canvas_scale
        @slider_handle.y = SLIDER_HEIGHT/2
        handle_rect = new Rectangle(@slider_handle.x-SLIDER_HANDLE_RADIUS, @slider_handle.y-SLIDER_HANDLE_RADIUS, SLIDER_HANDLE_RADIUS*2, SLIDER_HANDLE_RADIUS*2)
        left_rect = new Rectangle(@slider_box.x-SLIDER_SIDE_WIDTH/2, @slider_box.y, SLIDER_SIDE_WIDTH, SLIDER_HEIGHT)
        right_rect = new Rectangle(@slider_box.x+slider_width-SLIDER_SIDE_WIDTH/2, @slider_box.y, SLIDER_SIDE_WIDTH, SLIDER_HEIGHT)
        if not old_handle
            @stage.add_cursor('slider handle', 200, handle_rect, 'move')
            @stage.add_cursor('left slider side', 100, left_rect, 'w-resize')
            @stage.add_cursor('right slider side', 100, right_rect, 'w-resize')
        else
            @stage.modify_cursor('slider handle', handle_rect)
            @stage.modify_cursor('left slider side', left_rect)
            @stage.modify_cursor('right slider side', right_rect)
        @stage.update()


constrain_zoom = (drag_distance) ->
    return [Math.max(0, drag_distance+zoom_start), Math.min(sound_info.duration, drag_distance+zoom_stop)]
    # FIXME
    new_start = drag_distance+zoom_start
    new_stop = drag_distance+zoom_stop
    zoom_size = zoom_stop-zoom_start
    if new_start < 0
        [0, (zoom_size/2+new_start)*2]
    else if new_stop > sound_info.duration
        [sound_info.duration-(sound_info.duration-(zoom_size/2+new_start))*2, sound_info.duration]
    [new_start, new_stop]

hit_mouse = (object, stageX, stageY) ->
    object.hitTest(stageX-object.x, stageY-object.y)

save_mark = (mark) ->
    for i in [0...sound_info.marks.length]
        if sound_info.marks[i].id == mark.id
            return sound_info.marks[i] = mark
    sound_info.marks.push(mark)

delete_mark = (id) ->
    for i in [0...sound_info.marks.length]
        if sound_info.marks[i].id == id
            return sound_info.marks.splice(i, 1)

sync_mark = (mark) ->
    socket.emit 'add_mark',
        sound: sound_info._id
        id: mark.id
        pos: mark.pos
        label: mark.label

# TODO z-indexed events
# TODO displayobject-specific events
# TODO transparent active/inactive (or more) stages

$ ->
    container = $('#container')
    active_canvas = $('#active')
    base_canvas = $('#base')
    canvas_offset = active_canvas.offset()

    zoom_start = 0
    zoom_stop = sound_info.duration
    canvas_scale = sound_info.duration/active_canvas.width()

    active_stage = new Transcribe(active_canvas[0], new Stage(base_canvas[0]))

    hover_mark_line = null

    ###
    active_canvas.mousemove (event) ->
        stageX = event.pageX-canvas_offset.left
        stageY = event.pageY-canvas_offset.top
        if dragging
            active_stage.addChild(drag_rect)
        else if dragging_slider
        else if dragging_line?
            dragging_line.line.x = stageX
            dragging_line.label.css(left: (canvas_offset.left+stageX)+'px')

        cursor = if update_hover_mark_line = hit_mark_line(stageX, stageY)
            hover_mark_line = update_hover_mark_line
            line_color = MARK_LINE_HOVER_COLOR
            cursor_line.visible = false
            'e-resize'
        else
            if hover_mark_line?
                update_hover_mark_line = hover_mark_line
                line_color = MARK_LINE_COLOR
                hover_mark_line = null
            if slider_handle and hit_mouse(slider_handle, stageX, stageY)
                'move'
            else if dragging
                'e-resize'
            else if stageY < GRAPH_HEIGHT
                'crosshair'
            else
                'default'

        if update_hover_mark_line
            stack_offset = update_hover_mark_line.label.offset().top-active_canvas.offset().top-GRAPH_HEIGHT
            update_hover_mark_line.line.graphics = WidgetLine(@stage, stack_offset, line_color).graphics

        active_canvas.css('cursor', cursor)
        active_stage.update()

    # TODO displayobject-specific events

    $(document).mouseup (event) ->
        stageX = event.pageX-canvas_offset.left
        cur_scale = (zoom_stop - zoom_start)/active_canvas.width()

        if dragging and drag_start != stageX
        else if dragging_slider
        else if dragging_line?
            dragging_line.mark.pos = dragging_line.line.x*cur_scale+zoom_start
            update_widget(dragging_line)
            move_widgets()
    ###

    add_message = (sender, message) ->
       $('<p>').text("#{sender}: #{message}").appendTo($('#chat-messages'))

    socket.on 'receive_message', (data) -> add_message(data.sender, data.message)

    $('#chat-input').keypress (event) ->
        if event.which == 13
            sender = sound_info.user_id
            message = $(this).val()
            add_message(sender, message)
            $(this).val('')
            socket.emit 'send_message',
                sender: sender
                message: message

    active_stage.update()
