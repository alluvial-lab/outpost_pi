/// Report the outcome of an extension or supervisor installation from onboarding.
///
/// [ok] indicates success. [detail] carries an error message, or an optional
/// success summary, for display in the dialog.
class InstallResult {
  const InstallResult.success([this.detail = '']) : ok = true;
  const InstallResult.failure(this.detail) : ok = false;

  final bool ok;
  final String detail;
}
