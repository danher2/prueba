OneNote Viewer
==============

Reads your OneNote section files (.one) WITHOUT the OneNote app and builds a
browsable, searchable copy of all your notes that opens in any web browser.

Your original files are only read. Nothing is changed, uploaded or sent anywhere.
Everything runs on your own machine.

What you need
-------------
Python 3.8 or newer. No pip installs and no internet are needed - everything is
in this folder.

How to run it (Windows)
-----------------------
Easiest: drag the folder that holds your notebooks onto "Open my notebooks.bat".
(Or double-click it and paste the folder path when it asks.)

Or from a Command Prompt in this folder:

    python onenote_viewer.py "C:\path\to\Notebooks"

Point it at the folder that contains your notebook folders, for example:

    Notebooks\
        Dayli\        <- notebook (its .one files are the sections)
            Oct 2026.one
            Sep 2024.one
            Open Notebook.onetoc2
        Work\
        Personal\

You can also pass several folders, single .one files, or .onepkg files.

When it finishes, it opens "OneNote Viewer\index.html" (created next to the
folder you gave it). Use -o "C:\some\other\folder" to choose where it goes.

Using the viewer
----------------
- Left side: notebooks > sections > pages, with the page date.
- Search box (press /): searches every page of every notebook at once.
  Matches are highlighted; use the up/down arrows at the top to jump between them.
- "Copy page": copies the page so you can paste it into a page in OneNote web
  (text, formatting, lists and tables come across; re-insert images by hand).
- Images open full size when clicked. Attachments download when clicked.
- Alt+Up / Alt+Down: previous / next page.

What it reads
-------------
Text and formatting (bold, italic, underline, strikethrough), headings,
indentation, bullets and numbering, to-do checkboxes, tables, links, images,
attached files, text from printouts, page titles and dates.

Not shown: handwriting/ink drawings, and exact positions of note containers
on the page (content is shown top to bottom).

If a section shows "text only"
------------------------------
That section's format couldn't be fully read (for example sections downloaded
from OneDrive/SharePoint, or very old OneNote 2007 files). The viewer then shows
all the text it could recover from the file. report.txt lists every section and
how it was read.

Credits
-------
Uses a patched copy of pyOneNote by Amirreza Niakanlahiji (Apache License 2.0,
see pyOneNote/LICENSE). Changes are marked "[onenote_viewer patch]" in
pyOneNote/FileNode.py: reading edited (revised) objects, large/read-only object
declarations, object-reference lists, nested property arrays, and skipping
unknown records safely.
