namespace PixelSaver {
public class TitleBarManager : Object {

    private Wnck.Screen screen;
    private Wnck.Window? active_window;

    private static TitleBarManager? instance;

    private int references;
    private string[] blacklist_apps;

    public static TitleBarManager INSTANCE {
        get {
            if(instance == null){
                instance = new TitleBarManager();
            }
            return instance;
        }
    }

    public signal void on_title_changed (string title);
    public signal void on_window_state_changed (bool is_maximized);
    public signal void on_active_window_changed (bool can_minimize,
        bool can_maximize,
        bool can_close,
        bool is_active_window_csd,
        bool is_active_window_maximized,
        bool force_hide);

    /*
     * Should call this at constructor
     */
    public void register(){
        references++;
    }

    /*
     * Should call this at destructor
     */
    public void unregister(){
        if(--references <= 0){
            instance = null;
        }
    }

    private TitleBarManager()
    {
        this.screen = Wnck.Screen.get_default();
        this.active_window = this.screen.get_active_window();

        this.screen.active_window_changed.connect( this.on_wnck_active_window_changed );
        this.screen.window_opened.connect( this.on_window_opened );
        this.screen.force_update();
        unowned List<Wnck.Window> windows = this.screen.get_windows_stacked();
        foreach(Wnck.Window window in windows){
            if(window.get_window_type() != Wnck.WindowType.NORMAL) continue;

            this.toggle_title_bar_for_window(window, false);
        }
        this.on_wnck_active_window_changed(this.screen.get_active_window());

        this.screen.window_closed.connect( (w) => {
            //this.screen.force_update();
            this.on_wnck_active_window_changed(w);
        });
    }

    ~TitleBarManager() {
        unowned List<Wnck.Window> windows = this.screen.get_windows_stacked();
        foreach(Wnck.Window window in windows){
            if(window.get_window_type() != Wnck.WindowType.NORMAL) continue;

            this.toggle_title_bar_for_window(window, true);
        }
    }

    public Wnck.ActionMenu? get_action_menu_for_active_window() {
        return new Wnck.ActionMenu(this.active_window);
    }

    public bool check_valid_app(string[] blacklist_apps) {
        this.blacklist_apps = blacklist_apps;
        if (this.active_window != null && this.blacklist_apps != null && blacklist_apps.length > 0) {
            if (!this.active_window.has_name()) return false;
            string? app_name = this.active_window.get_class_group_name();
            foreach (string val in this.blacklist_apps) {
                if(val == app_name) {
                    return true;
                }
            }
        }

        return false;
    }

    public void close_active_window(){
        if(this.active_window == null) return;

        this.active_window.close(this.get_x_server_time());
    }

    public void toggle_maximize_active_window(){
        if(this.active_window == null) return;

        if(this.active_window.is_maximized()){
            this.active_window.unmaximize();
        } else {
            this.active_window.maximize();
        }
    }

    public void minimize_active_window(){
        if(this.active_window == null) return;

        this.active_window.minimize();
    }

    private void toggle_title_bar_for_window(Wnck.Window window, bool is_on){

    }

    private bool is_window_csd(Wnck.Window window){
        try {
            string[] spawn_args = {"xprop", "-id",
                "%#.8x".printf((uint)window.get_xid()), "_MOTIF_WM_HINTS"};
            string[] spawn_env = Environ.get ();
            string ls_stdout;
            string ls_stderr;
            int ls_status;

            Process.spawn_sync ("/",
                spawn_args,
                spawn_env,
                SpawnFlags.SEARCH_PATH,
                null,
                out ls_stdout,
                out ls_stderr,
                out ls_status);

            if(ls_stdout.strip() == "_MOTIF_WM_HINTS(_MOTIF_WM_HINTS) = 0x2, 0x0, 0x0, 0x0, 0x0"){
                return true;
            }
        } catch(SpawnError e){
            error(e.message);
        }
        return false;
    }

    private void change_titlebar() {
        if (active_window == null || is_window_csd(active_window)) return;
        try {
                bool hide_titlebar = false;
                if (this.active_window.is_maximized()){
                    hide_titlebar = true;
                }
                string[] spawn_args = {"xprop", "-id", "%#.8x".printf((uint)active_window.get_xid()),
                    "-f", "_MOTIF_WM_HINTS", "32c", "-set",
                    "_MOTIF_WM_HINTS", hide_titlebar ? "0x2, 0x0, 0x2, 0x0, 0x0" : "0x2, 0x0, 0x1, 0x0, 0x0"};
                string[] spawn_env = Environ.get ();
                Pid child_pid;

                Process.spawn_async ("/",
                    spawn_args,
                    spawn_env,
                    SpawnFlags.SEARCH_PATH | SpawnFlags.DO_NOT_REAP_CHILD,
                    null,
                    out child_pid);
                ChildWatch.add (child_pid, (pid, status) => {
                    // Triggered when the child indicated by child_pid exits
                    Process.close_pid (pid);
                });
            } catch(SpawnError e) {
                error(e.message);
            }
    }

    private void on_wnck_active_window_changed(Wnck.Window? previous_window){
        if(previous_window != null){
            previous_window.name_changed.disconnect( this.on_active_window_name_changed );
            previous_window.state_changed.disconnect( this.on_active_window_state_changed );
        }

        bool can_minimize = false;
        bool can_maximize = false;
        bool can_close = false;
        bool is_csd = false;
        bool is_maximized = false;
        bool force_hide = false;

        this.active_window = this.screen.get_active_window();
        if(this.active_window != null && this.active_window.get_window_type() != Wnck.WindowType.NORMAL){
            this.active_window = null;
        }

        if (this.check_valid_app(blacklist_apps)) {
            this.active_window = null;
            force_hide = true;
        }

        if(this.active_window != null){
            Wnck.WindowActions actions = this.active_window.get_actions();
            can_minimize = (actions & Wnck.WindowActions.MINIMIZE) > 0;
            can_maximize = (actions & Wnck.WindowActions.MAXIMIZE) > 0;
            can_close = (actions & Wnck.WindowActions.CLOSE) > 0;
            is_csd = this.is_window_csd(this.active_window);
            is_maximized = this.active_window.is_maximized();

            this.active_window.name_changed.connect( this.on_active_window_name_changed );
            this.active_window.state_changed.connect( this.on_active_window_state_changed );
            this.on_title_changed(this.active_window.get_name());
        } else {
            this.on_title_changed("");
        }
        change_titlebar();
        this.on_active_window_changed(can_minimize, can_maximize, can_close, is_csd, is_maximized, force_hide);
    }

    private void on_window_opened(Wnck.Window window){
        this.toggle_title_bar_for_window(window, false);
    }

    private void on_active_window_name_changed(){
        this.on_title_changed(this.active_window.get_name());
    }

    private void on_active_window_state_changed(Wnck.WindowState changed_mask, Wnck.WindowState new_state){
        change_titlebar();
        this.on_window_state_changed(this.active_window.is_maximized());
    }

    private uint32 get_x_server_time() {
        unowned X.Window xwindow = Gdk.X11.get_default_root_xwindow();
        unowned X.Display xdisplay = Gdk.X11.get_default_xdisplay();
        Gdk.X11.Display display = Gdk.X11.Display.lookup_for_xdisplay(xdisplay);
        Gdk.X11.Window window = new Gdk.X11.Window.foreign_for_display(display, xwindow);
        return Gdk.X11.get_server_time(window);
    }
}
}
