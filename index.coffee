{argNames, makeId} = require 'lodash-fork'
debugError = require('debug-fork') 'error'
errPending = {}

module.exports = class Outlet
  (@roots = []).depth = 0

  constructor: (value, @context, auto) ->
    @auto = if auto then this else null
    @index = makeId()

    @equivalents = {}
    (@changing = {}).length = 0
    @outflows = {}

    @set value

  @block = (fn) ->
    ->
      Outlet.openBlock()
      try
        fn.apply this, arguments
      finally
        Outlet.closeBlock()

  @openBlock = ->
    ++Outlet.roots.depth
    return

  @closeBlock = ->
    unless --(roots = Outlet.roots).depth
      ++roots.depth
      `for (var i = 0, len = 0; (i < len) || (i < (len = roots.length)); ++i) roots[i]._runSource();`
      --roots.depth
      roots.length = 0
    return

  toString: -> @index

  'toOJSON': ->
    if @value? then @value else null

  set: (value, version) ->
    Outlet.openBlock()
    if typeof value is 'function'
      @_setFunc value, version
    else if value instanceof Outlet
      @_setOutlet value
    else
      @_setFA value, version
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

      if @value is value and @version is version
        return @_setPendingFalse()

      @pending = false

      @['value'] = @value = value
      @version = version

      if immediate
        outflow._runSource this for index, outflow of @outflows
      else
        for index, outflow of @outflows
          if outflow.changing[this]
            delete outflow.changing[this]
            --outflow.changing.length
          unless outflow.root
            outflow.root = true
            Outlet.roots.push outflow
            outflow._setPendingTrue()

    equiv._setFA value, version, this, immediate for index, equiv of @equivalents when equiv isnt except

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
      @version = makeIndex()
    else
      @set @value, makeIndex()
    @value

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
    unless outlet
      for index, outlet of @equivalents
        delete @equivalents[index]
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
    Outlet.closeBlock()
    return

  @prototype['clear'] = @prototype.clear = ->
    for index, outlet of @equivalents
      delete @equivalents[index]
      delete outlet.equivalents[this]
      outlet._setPendingFalse() unless outlet._shouldPend {}
    @set()
    return

  _shouldPend: (visited) ->
    return true if @changing.length or @root
    visited[this] = 1
    for index, outlet of @equivalents when !visited[index] and outlet._shouldPend(visited)
      return true
    false

  _setPendingTrue: (source) ->
    @changing[source] = ++@changing.length if source and !@changing[source]
    unless @pending
      @pending = true
      except = @funcOutlet if @changing.length or @root
      equiv._setPendingTrue() for index, equiv of @equivalents when equiv isnt except
      outflow._setPendingTrue(this) for index, outflow of @outflows
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

    else unless @funcOutlet?.pending and @funcOutlet._shouldPend {}
      @pending = false

      for index, equiv of @equivalents
        if equiv.value is @value and equiv.version is @version
          equiv._setPendingFalse()
        else
          equiv._setFA @value, @version, this, true

      outflow._setPendingFalse(this) for index, outflow of @outflows

    return

  _runSource: (source) ->
    if source
      if @changing[source]
        delete @changing[source]
        --@changing.length
      return if @root
    else if @changing.length
      Outlet.roots.push this
      return

    @root = false
    return unless @pending and !@changing.length

    prev = Outlet.auto; Outlet.auto = @auto
    try
      @_autoInflows[index] = 0 for index of @_autoInflows
      value = @_runFunc()
      for index,used of @_autoInflows when !used
        delete @_autoInflows[index]
        delete @autoInflows[index].outflows[this]
        delete @autoInflows[index]
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
