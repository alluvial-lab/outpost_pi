/// Represent an image attached to a prompt.
///
/// It becomes `ImageContent` on the `pi --mode rpc` wire as
/// `{type:'image', data:<base64>, mimeType}` in the `prompt` command's `images`
/// field.
class PromptImage {
  const PromptImage({required this.data, required this.mimeType});

  /// Base64 content without the `data:` prefix.
  final String data;

  /// MIME type, such as `image/png` or `image/jpeg`.
  final String mimeType;
}
