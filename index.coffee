{argNames, makeId} = require 'lodash-fork'
require 'debug-fork'
debugError = global.debug 'error'
OJSON = require 'ojson'
errPending = {}

sameValue = (a, b) ->
  return true if a is b
  return false if !a? or (ta = typeof a) isnt typeof b or ta isnt 'object' or !Array.isArray(a) or !Array.isArray(b) or (len = a.length) isnt b.length
  `for (var i = 0; i < len; ++i) { if (a[i] !== b[i]) return false; }`
  true

module.exports = class Outlet
  (@roots = []).depth = 0
  @tails = []

  constructor: (value, @context, auto) ->
    @auto = if auto then this else null
    @id = makeId()

    @equivalents = {}
    (@changing = {}).length = 0
    @outflows = {}

    @set value

  @block = (fn) ->
    ret = ->
      Outlet.openBlock()
      try
        fn.apply this, arguments
      finally
        Outlet.closeBlock()
    ret.inblock = true
    ret

  @openBlock = ->
    ++Outlet.roots.depth
    return

  @closeBlock = ->
    unless --(roots = Outlet.roots).depth
      ++roots.depth
      tails = Outlet.tails
      `
      var j = 0, lenTail = 0, i = 0, len = 0;
      for (;;) {
        for (; (i < len) || (i < (len = roots.length)); ++i) { roots[i].root = false; roots[i]._runSource(); }
        if ((j < lenTail) || (j < (lenTail = tails.length))) {
          tails[j++]();
        } else {
          break;
        }
      }
      `
      --roots.depth
      roots.length = 0
      tails.length = 0
    return

  @atEnd = (fn) ->
    if @roots.depth
      @tails.push fn
    else
      fn()
    return

  toString: -> @id

  'toOJSON': ->
    if @value? then OJSON.toOJSON(@value) else null

  set: (value, version) ->
    Outlet.openBlock()
    try
      if typeof value is 'function'
        @_setFunc value, version
      else if value instanceof Outlet
        @_setOutlet value
      else
        @_setFA value, version
    finally
      Outlet.closeBlock()
    return

  initProxy: (func, context) ->
    @['_fA'] = @value
    @['_fE'] = @version
    @_setFunc func, context
    return

  _setFA: (value, version, source, immediate) ->
    if @root or @changing.length

      if !(except = @funcOutlet) or source isnt except
        return if @hasOwnProperty('_fA') and @['_fA'] is value and @['_fE'] is version
        @['_fA'] = value
        @['_fE'] = version
        except?._setPendingTrue()
      else
        return

    else

      if @version is version and sameValue(@value, value)
        return @_setPendingFalse()

      @pending = false

      @['value'] = @value = value
      @version = version

      if immediate
        outflow._runSource this for id, outflow of @outflows
      else
        for id, outflow of @outflows
          if outflow.changing[this]
            delete outflow.changing[this]
            --outflow.changing.length
          unless outflow.root
            outflow.root = true
            Outlet.roots.push outflow
            outflow._setPendingTrue()

    equiv._setFA value, version, this, immediate for id, equiv of @equivalents when equiv isnt except

    return

  _setOutlet: (outlet) ->
    unless @equivalents[outlet]
      @equivalents[outlet] = outlet
      outlet.equivalents[this] = this
      if outlet.pending
        @_setPendingTrue()
      else
        @_setFA outlet.value, outlet.version
    return

  _setFunc: (@func, context) ->
    context && @context = context
    @funcArgOutlets = []
    (@funcArgOutlets[i] = @context[name]).addOutflow this for name,i in argNames func
    @auto = null if i # TODO this is a workaround in lieu of a yet unimplemented better alternative
    @_setPendingTrue()
    @root = true
    Outlet.roots.push this
    return

  @prototype['modified'] = @prototype.modified = ->
    if @pending
      @version = makeId()
    else
      @set @value, makeId()
    @value

  push: (value) ->
    if @value and @value.push
      @value.push value
      @modified()
    else
      @set [value]
    return

  pop: ->
    return unless @value and @value.pop and @value.length > 0
    ret = @value.pop()
    @modified()
    ret

  get: ->
    if (out = Outlet.auto) and this != out
      a = out._autoInflows ||= {}
      if a[this]?
        a[this] = 1
      else unless @outflows[out]
        a[this] = (out.autoInflows ||= {})[this] = this
        @outflows[out] = out
        if @pending
          out.changing[this] = ++out.changing.length
          throw errPending

    if @value and len = arguments.length
      if @value.get?.length > 0
        return @value.get(arguments...)
      else if len is 1 and typeof @value is 'object'
        return @value[arguments[0]]
    
    @value

  addOutflow: (outflow) ->
    outflow = new Outlet outflow if typeof outflow is 'function'
    unless @outflows[outflow]
      @outflows[outflow] = outflow
      outflow._setPendingTrue this if @pending
    outflow

  removeOutflow: (outflow) ->
    if @outflows[outflow]
      delete @outflows[outflow]
      outflow._setPendingFalse this if @pending
    return

  @prototype['unset'] = @prototype.unset = (outlet) ->
    Outlet.openBlock()
    try
      unless outlet
        for id, outlet of @equivalents
          delete @equivalents[id]
          delete outlet.equivalents[this]
          outlet._setPendingFalse() unless outlet._shouldPend {}

        @_setPendingFalse() unless @_shouldPend {}
      else
        return unless @equivalents[outlet]
        delete @equivalents[outlet]
        delete outlet.equivalents[this]
        if @pending
          unless outlet._shouldPend({})
            outlet._setPendingFalse()
          else unless @_shouldPend({})
            @_setPendingFalse()
    finally
      Outlet.closeBlock()
    return

  _shouldPend: (visited) ->
    return true if @changing.length or @root
    visited[this] = 1
    for id, outlet of @equivalents when !visited[id] and outlet._shouldPend(visited)
      return true
    false

  _setPendingTrue: (source) ->
    @changing[source] = ++@changing.length if source and !@changing[source]
    unless @pending
      @pending = true
      except = @funcOutlet if @changing.length or @root
      equiv._setPendingTrue() for id, equiv of @equivalents when equiv isnt except
      outflow._setPendingTrue(this) for id, outflow of @outflows
    return

  _setPendingFalse: (source) ->
    if source and @changing[source]
      delete @changing[source]
      --@changing.length

    return if !@pending or @root or @changing.length

    if @hasOwnProperty '_fA'
      value = @['_fA']; delete @['_fA']
      version = @['_fE']; delete @['_fE']
      @_setFA value, version, source, true

    else if @funcOutlet and !@funcOutlet.pending and (@funcOutlet.version isnt @version or !sameValue(@funcOutlet.value,@value))
      @_setFA @funcOutlet.value, @funcOutlet.version

    else unless @funcOutlet?.pending and @funcOutlet._shouldPend {}
      @pending = false

      for id, equiv of @equivalents
        if equiv.version is @version and sameValue(equiv.value,@value)
          equiv._setPendingFalse()
        else
          equiv._setFA @value, @version, this, true

      outflow._setPendingFalse(this) for id, outflow of @outflows

    return

  _runSource: (source) ->
    if source
      if @changing[source]
        delete @changing[source]
        --@changing.length
      return if @root

    if @changing.length
      unless @root
        Outlet.roots.push this
        @root = true
      return

    return unless @pending

    prev = Outlet.auto; Outlet.auto = @auto
    try
      @_autoInflows[id] = 0 for id of @_autoInflows
      value = @_runFunc()
      for id,used of @_autoInflows when !used
        delete @_autoInflows[id]
        delete @autoInflows[id].outflows[this]
        delete @autoInflows[id]
    catch _error
      return if _error is errPending
      debugError "#{_error.name}: #{_error.message}\n #{_error.stack}" if _error
    finally
      Outlet.auto = prev

    if value isnt outlet = @funcOutlet
      if outlet
        @root = true
        delete @equivalents[outlet]
        delete outlet.equivalents[this]
        outlet._setPendingFalse() if outlet.pending and !outlet._shouldPend {}
        @root = false
        delete @funcOutlet
      if value instanceof Outlet
        @funcOutlet = value
        @equivalents[value] = value
        value.equivalents[this] = this

    if @hasOwnProperty '_fA'
      @funcOutlet?._setPendingTrue()
      value = @['_fA']; delete @['_fA']
      version = @['_fE']; delete @['_fE']
    else if value instanceof Outlet
      version = value.version
      value = value.value

    @_setFA value, version, this, true
    return

  _runFunc: ->
    @funcArgs ||= []
    if @funcArgOutlets
      @funcArgs[i] = outlet.value for outlet, i in @funcArgOutlets
    @func.apply @context, @funcArgs
