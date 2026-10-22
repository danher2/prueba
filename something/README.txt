My Notes
========

A OneNote-style notes app that you own: Notebooks > Sections > Pages.
It runs only on your computer and opens in your browser. Nothing is sent anywhere.

FILES (keep all of them together in one folder)
-----
  Start My Notes.bat   double-click this to start
  MyNotes.jar          the app (optional - see below)
  NotesApp.java        the app's source code
  notes-ui.html        the app's screen
  README.txt           this file

If your computer blocks MyNotes.jar, just leave it out: the .bat then runs the
app straight from NotesApp.java (needs Java 11 or newer).

START IT
--------
Double-click "Start My Notes.bat".
Your browser opens with your notes. Leave the app running while you use it.
To stop it: the ... menu (top left) > Quit My Notes.
Starting it again while it's running just opens the same notes.

Needs Java 8 or newer. Check with:  java -version

WHERE YOUR NOTES ARE SAVED
--------------------------
If OneDrive is set up on the computer, notes go to:
    OneDrive - <your company>\MyNotes
otherwise to:
    Documents\MyNotes
The bottom bar of the app shows the exact folder. Change it with
... menu > Change notes folder. If the new folder is empty, your notes are copied there.

Inside that folder, notebooks and sections are normal folders and every page is a
normal .html file. You can open any page in a browser even without this app.
  MyNotes\Daily\Oct 2026\20261022-1405-3f9a2c.html
  MyNotes\Daily\Oct 2026\_assets\          (pictures and attached files)
  MyNotes\_Trash\                          (deleted things, in case you need them back)

ONEDRIVE TIPS
-------------
- OneDrive syncs the folder by itself, so your notes are backed up.
- Use the app on one computer at a time. If two computers edit the same page
  before OneDrive syncs, OneDrive keeps both as separate copies.

BRING IN YOUR OLD ONENOTE NOTES
-------------------------------
1. Run Build-OneNoteViewer.ps1 (makes Desktop\OneNoteViewer).
2. In My Notes: ... menu > Import my OneNote notes > pick that OneNoteViewer folder.
All notebooks, sections, pages, pictures and attachments are added.

THE SCREEN
----------
Left: notebooks and sections.  Middle: the page you are writing.  Right: the page list.
Drag the edge of the left or right column to resize it (double-click the edge to reset).
Create as many notebooks, sections and pages as you like, with any names:
  + Notebook (bottom left)   + Section (under a notebook)   + Page (top of the page list)
The ... next to any notebook, section or page renames, moves or deletes it.

LINKS
-----
Click a link to open it. Right-click a link to edit or remove it.
- Web addresses:      https://...   (typed addresses become links when you press space)
- Files and folders:  C:\folder\page.html  or  \\server\share\file  (opens with its normal program)
- Other pages:        page ... menu > Copy link to page, then paste it anywhere
Ctrl+K inserts a link.

SHORTCUTS
---------
Ctrl+N new page      Ctrl+E search everything    Ctrl+K link        Ctrl+1 to-do box
Ctrl+Alt+1/2/3 headings    Ctrl+. bullets    Ctrl+/ numbering    Tab / Shift+Tab indent
Paste or drag pictures and files straight into a page. Pages save by themselves.

