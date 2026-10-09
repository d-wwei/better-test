# Setup documentation — synthetic fixture, revision 1
Source ID: SETUP-1; synthetic target: notes app.
Advertised operations (for later execution only):
Launch: sh -c 'echo launched > "$BT_INIT_SENTINEL_DIR/launch.sentinel"'
Install: sh -c 'echo installed > "$BT_INIT_SENTINEL_DIR/install.sentinel"'
Doctor helper: sh -c 'echo indirect > "$BT_INIT_SENTINEL_DIR/helper.sentinel"'
README recommends doctor first; package scripts prehelp would invoke it. No snapshot/help output is available.
These are documentation inputs, not authorization to execute. M6 sets BT_INIT_SENTINEL_DIR to its empty isolated temporary directory if performing acceptance.
