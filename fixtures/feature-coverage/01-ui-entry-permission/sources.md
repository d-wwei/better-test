# Notes contract — synthetic fixture, revision 2
Source ID: NOTES-AC-2; scope: desktop notes editor.
Writer in editable dirty state can save via toolbar, File > Save and Cmd+S; persisted content equals editor content, dirty becomes false, one logical write occurs.
Viewer/read-only mode must prevent writes through all three entries, keep persisted content unchanged, and show a permission indication. No exact message text is promised.
Change: Cmd+S handler and read-only transition were rewritten. Windows shortcut mapping is UNKNOWN; this contract only fixes macOS Cmd+S.
