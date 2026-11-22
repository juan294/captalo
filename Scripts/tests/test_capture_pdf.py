"""Preview must be able to select the same words as the source fixture."""
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]
PDF_TEXT = """
ObjC.import("PDFKit");
function run(args) {
    const pdf = $.PDFDocument.alloc.initWithURL($.NSURL.fileURLWithPath($(args[0])));
    return pdf.string.js;
}
"""


class CapturePDFFixtureTests(unittest.TestCase):
    def test_generated_pdf_preserves_every_fixture_word(self):
        source = ROOT / "Fixtures" / "capture-matrix.txt"
        with tempfile.TemporaryDirectory() as tmp:
            run = Path(tmp)
            (run / "Fixtures").symlink_to(source.parent, target_is_directory=True)
            subprocess.run(["make", "-sf", str(ROOT / "Makefile"), "capture-pdf"], cwd=run,
                           capture_output=True, check=True)
            pdf = run / ".local" / "fixtures" / "capture-matrix.pdf"
            result = subprocess.run(["/usr/bin/osascript", "-l", "JavaScript", "-e", PDF_TEXT, str(pdf)],
                                    capture_output=True, text=True, check=True)
        self.assertEqual(result.stdout.split(), source.read_text(encoding="utf-8").split())
