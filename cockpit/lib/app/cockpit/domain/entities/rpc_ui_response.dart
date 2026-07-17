/// The mutually exclusive payload for an interactive RPC UI response.
///
/// Wire keys are intentionally absent here; [PiRpcProcess] owns translating
/// these domain values to the `extension_ui_response` command shape.
sealed class RpcUiResponse {
  const RpcUiResponse();
}

/// A textual answer for select, input, or editor requests.
final class RpcUiValueResponse extends RpcUiResponse {
  const RpcUiValueResponse(this.value);

  final String value;
}

/// A yes/no answer for a confirmation request.
final class RpcUiConfirmationResponse extends RpcUiResponse {
  const RpcUiConfirmationResponse(this.confirmed);

  final bool confirmed;
}

/// Cancellation of an interactive RPC UI request.
final class RpcUiCancelledResponse extends RpcUiResponse {
  const RpcUiCancelledResponse();
}
