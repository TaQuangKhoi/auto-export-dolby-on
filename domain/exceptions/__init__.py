class DolbyAutomationError(BaseException):
    pass


class AdbNotFoundError(DolbyAutomationError):
    pass


class AdbCommandError(DolbyAutomationError):
    pass


class UiDumpError(DolbyAutomationError):
    pass


class ElementNotFoundError(DolbyAutomationError):
    pass


class ExportError(DolbyAutomationError):
    pass


class DeleteError(DolbyAutomationError):
    pass


class TrackNotFoundError(DolbyAutomationError):
    pass


class ConfigurationError(DolbyAutomationError):
    pass