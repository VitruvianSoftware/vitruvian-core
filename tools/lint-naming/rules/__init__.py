# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

"""Naming convention rule definitions and validators."""

from dataclasses import dataclass
from enum import Enum
from typing import Optional, List, Dict, Any


class ViolationSeverity(str, Enum):
    ERROR = "ERROR"
    WARNING = "WARNING"
    INFO = "INFO"


@dataclass
class NamingViolation:
    rule_id: str
    file_path: str
    line_number: Optional[int]
    message: str
    severity: ViolationSeverity = ViolationSeverity.ERROR
    suggested_fix: Optional[str] = None

    def format_line(self) -> str:
        loc = (
            f"{self.file_path}:{self.line_number}"
            if self.line_number
            else self.file_path
        )
        fix_str = f" (suggested: '{self.suggested_fix}')" if self.suggested_fix else ""
        return f"{loc}: [{self.rule_id}] {self.severity.value}: {self.message}{fix_str}"

    def to_dict(self) -> Dict[str, Any]:
        return {
            "rule_id": self.rule_id,
            "file_path": self.file_path,
            "line_number": self.line_number,
            "severity": self.severity.value,
            "message": self.message,
            "suggested_fix": self.suggested_fix,
        }
