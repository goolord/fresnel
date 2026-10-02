// Bindings to the parts of Cmajor's PatchConnection that the view and the worker use.

type t

type parameterEvent = {endpointID: string, value: float}
type storedStateEvent = {key: string, value: JSON.t}

// Whatever readResource resolves to: a fetch Response in the WebAudio runtime (and from
// Resources.res's fetch in the native view); an array of (signed) byte values or a string in
// the native worker.
type resource

@send
external addAllParameterListener: (t, parameterEvent => unit) => unit = "addAllParameterListener"
@send
external removeAllParameterListener: (t, parameterEvent => unit) => unit =
  "removeAllParameterListener"

@send external sendEventOrValue: (t, string, 'value) => unit = "sendEventOrValue"
// Sends without ramping, and waits up to a second for the patch to accept it.
@send
external sendEventOrValueNow: (t, string, 'value, @as(-1) _, @as(1000) _) => unit =
  "sendEventOrValue"
@send external sendParameterGestureStart: (t, string) => unit = "sendParameterGestureStart"
@send external sendParameterGestureEnd: (t, string) => unit = "sendParameterGestureEnd"

@send
external addStoredStateValueListener: (t, storedStateEvent => unit) => unit =
  "addStoredStateValueListener"
@send
external removeStoredStateValueListener: (t, storedStateEvent => unit) => unit =
  "removeStoredStateValueListener"
@send external requestStoredStateValue: (t, string) => unit = "requestStoredStateValue"
@send external sendStoredStateValue: (t, string, 'value) => unit = "sendStoredStateValue"

// The parameters that differ from their defaults, and every stored-state value, in one reply
// to this view.
type namedValue = {name: string, value: float}
type fullState = {parameters?: array<namedValue>, values?: dict<JSON.t>}
@send
external requestFullStoredState: (t, fullState => unit) => unit = "requestFullStoredState"

@send external addEndpointListener: (t, string, JSON.t => unit) => unit = "addEndpointListener"
@send
external removeEndpointListener: (t, string, JSON.t => unit) => unit = "removeEndpointListener"

// Only the WebAudio runtime's connection and the worker's have readResource; the native
// view's doesn't (Resources.res fetches instead).
@send external readResource: (t, string) => promise<resource> = "readResource"
@send external getResourceAddress: (t, string) => string = "getResourceAddress"
