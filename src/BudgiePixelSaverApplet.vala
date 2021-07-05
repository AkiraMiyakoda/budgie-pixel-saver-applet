
namespace PixelSaver {

const int VISIBILITY_TITLE_BUTTONS = 0;
const int VISIBILITY_TITLE = 1;
const int VISIBILITY_BUTTONS = 2;

const int TITLE_ALIGNMENT_LEFT  = 0;
const int TITLE_ALIGNMENT_RIGHT = 1;

const int TITLE_BUTTONS_SPACING = 7;

const Gtk.TargetEntry[] target_list = {
    { "application/budgie-pixel-saver-applet", 0, 0 }
};

public class Plugin : Budgie.Plugin, Peas.ExtensionBase
{
    public Budgie.Applet get_panel_widget(string uuid)
    {
        return new Applet(uuid);
    }
}

public class AppletContainer : Gtk.Box
{
    public AppletContainer (Gtk.Orientation orientation, int spacing) {
        this.orientation = orientation;
        this.spacing = spacing;
    }

    static construct {
        // This behaves like Gtk.HeaderBar in the CSS hierarchy.
        set_css_name ("headerbar");
    }
}

public class Applet : Budgie.Applet
{
    Gtk.Label title_label;
    Gtk.Button minimize_button;
    Gtk.Button maximize_button;
    Gtk.Button close_button;
    Gtk.Box button_box;
    Gtk.Image maximize_image;
    Gtk.Image restore_image;
    Gtk.EventBox title_box;
    AppletContainer applet_container;

    bool is_buttons_visible {get; set;}
    bool is_title_visible {get; set;}
    bool is_active_window_csd {get; set;}
    bool is_active_window_maximized {get; set;}
    bool force_hide {get; set;}

    public string uuid { public set; public get; }

    private Settings? settings;
    private Settings? blacklist_settings;
    private Settings? wm_settings;
    private bool theme_buttons = false;
    private bool theme_title = false;
    private int title_alignment = TITLE_ALIGNMENT_LEFT;
    private Budgie.PanelPosition panel_position = Budgie.PanelPosition.TOP;

    PixelSaver.TitleBarManager title_bar_manager;

    public Applet(string uuid)
    {
        Object(uuid: uuid);
        this.force_hide = true;
        this.title_bar_manager = PixelSaver.TitleBarManager.INSTANCE;
        this.title_bar_manager.register();

        this.minimize_button = new Gtk.Button.from_icon_name ("window-minimize-symbolic", Gtk.IconSize.BUTTON);
        this.maximize_button = new Gtk.Button.from_icon_name ("window-maximize-symbolic", Gtk.IconSize.BUTTON);
        this.close_button    = new Gtk.Button.from_icon_name ("window-close-symbolic",    Gtk.IconSize.BUTTON);

        this.button_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        this.button_box.pack_start (this.minimize_button, false, false, 0);
        this.button_box.pack_start (this.maximize_button, false, false, 0);
        this.button_box.pack_start (this.close_button,    false, false, 0);

        this.maximize_image = new Gtk.Image.from_icon_name ("window-maximize-symbolic", Gtk.IconSize.BUTTON);
        this.restore_image  = new Gtk.Image.from_icon_name ("window-restore-symbolic",  Gtk.IconSize.BUTTON);

        this.title_label = new Gtk.Label ("");
        this.title_label.set_ellipsize (Pango.EllipsizeMode.END);

        this.title_box = new Gtk.EventBox();
        this.title_box.add(this.title_label);

        this.applet_container = new AppletContainer (Gtk.Orientation.HORIZONTAL, 0);
        this.applet_container.pack_start (this.title_box,  false, false, 0);
        this.applet_container.pack_start (this.button_box, false, false, 0);
        this.add (this.applet_container);

        this.define_css_styles();
        this.set_css_styles();

        title_box.button_press_event.connect ((event) => {
            if (event.type == Gdk.EventType.@2BUTTON_PRESS){
                this.title_bar_manager.toggle_maximize_active_window();
            }
            return Gdk.EVENT_PROPAGATE;
        });

        title_box.button_release_event.connect ((event) => {
            if (event.button == 3) {
                Wnck.ActionMenu menu = this.title_bar_manager.get_action_menu_for_active_window();
                menu.popup(null, null, null, event.button, Gtk.get_current_event_time());
                return true;
            }
            return Gdk.EVENT_PROPAGATE;
        });

        this.minimize_button.clicked.connect (() => {
            this.title_bar_manager.minimize_active_window();
        });

        this.maximize_button.clicked.connect (() => {
            this.title_bar_manager.toggle_maximize_active_window();
        });

        this.close_button.clicked.connect (() => {
            this.title_bar_manager.close_active_window();
        });

        this.title_bar_manager.on_title_changed.connect((title) => {
            this.title_label.set_text(title);
            this.title_label.set_tooltip_text(title);
        });

        this.title_bar_manager.on_window_state_changed.connect((is_maximized) => {
            this.is_active_window_maximized = is_maximized;
            this.update_visibility();
            this.set_maximize_button_image();
        });

        this.title_bar_manager.on_active_window_changed.connect(
            (can_minimize, can_maximize, can_close, is_active_window_csd, is_active_window_maximized, force_hide) => {
                this.minimize_button.set_sensitive(can_minimize);
                this.maximize_button.set_sensitive(can_maximize);
                this.close_button.set_sensitive(can_close);
                this.is_active_window_csd = is_active_window_csd;
                this.is_active_window_maximized = is_active_window_maximized;
                this.force_hide = force_hide;
                this.update_visibility();
                this.set_maximize_button_image();
            }
        );

        settings_schema = "net.milgar.budgie-pixel-saver";
        settings_prefix = "/net/milgar/budgie-pixel-saver";

        this.settings = this.get_applet_settings(uuid);
        this.settings.changed.connect(on_settings_change);
        show_all();
        this.on_settings_change("size");
        this.on_settings_change("visibility");
        this.on_settings_change("theme-buttons");
        this.on_settings_change("title-alignment");

        wm_settings = new GLib.Settings("com.solus-project.budgie-wm");
        wm_settings.changed.connect(this.on_wm_settings_changed);
        this.on_wm_settings_changed("button-style");

        var blacklist_settings_schema = "net.milgar.budgie-pixel-saver.blacklist";

        blacklist_settings = new GLib.Settings(blacklist_settings_schema);
        blacklist_settings.changed.connect(on_blacklist_settings_change);
        this.on_blacklist_settings_change("blacklist-apps");

        this.drag_end.connect(this.on_drag_end);
    }

    ~Applet(){
        this.title_bar_manager.unregister();
    }

    private void define_css_styles() {
        string container_css = """
            .pixelsaver {
                min-height: unset;
                min-width:  unset;
                background-color: transparent;
                margin: -1px;
                border-width:  unset;
                border-radius: unset;
            }
            .pixelsaver-unset-title-theme {
                color: unset;
            }
            .pixelsaver-button  {
                min-width:  unset;
                min-height: unset;
            }
            """;

        Gdk.Screen screen=this.get_screen();
        Gtk.CssProvider css_provider = new Gtk.CssProvider();
        try {
            css_provider.load_from_data(container_css);
            Gtk.StyleContext.add_provider_for_screen(
                screen, css_provider, Gtk.STYLE_PROVIDER_PRIORITY_USER);
        }
        catch (Error e) {
            message("Could not load css %s", e.message);
        }
    }

    private void set_css_styles () {
        var container_context = this.applet_container.get_style_context();
        container_context.add_class("pixelsaver");

        if (theme_buttons) {
            var button_context = this.minimize_button.get_style_context();
            button_context.add_class("titlebutton");
            button_context.add_class("minimize");
            button_context.add_class("pixelsaver-button");

            button_context = this.maximize_button.get_style_context();
            button_context.add_class("titlebutton");
            button_context.add_class("maximize");
            button_context.add_class("pixelsaver-button");

            button_context = this.close_button.get_style_context();
            button_context.add_class("titlebutton");
            button_context.add_class("close");
            button_context.add_class("pixelsaver-button");
        } else {
            var button_context = this.minimize_button.get_style_context();
            button_context.remove_class("titlebutton");
            button_context.remove_class("minimize");
            button_context.remove_class("pixelsaver-button");

            button_context = this.maximize_button.get_style_context();
            button_context.remove_class("titlebutton");
            button_context.remove_class("maximize");
            button_context.remove_class("pixelsaver-button");

            button_context = this.maximize_button.get_style_context();
            button_context.remove_class("titlebutton");
            button_context.remove_class("close");
            button_context.remove_class("pixelsaver-button");
        }

        if (this.theme_title) {
            container_context.remove_class("pixelsaver-unset-title-theme");
        }
        else {
            container_context.add_class("pixelsaver-unset-title-theme");
        }
    }

    private void set_title_alignment() {
        float align = (this.title_alignment == TITLE_ALIGNMENT_LEFT) ? 0.0f : 1.0f;
        switch (this.panel_position) {
            case Budgie.PanelPosition.LEFT:
                this.title_label.set_alignment(0.5f, 1.0f - align);
                break;
            case Budgie.PanelPosition.RIGHT:
                this.title_label.set_alignment(0.5f, align);
                break;
            default:
                this.title_label.set_alignment(align, 0.5f);
                break;
        }
    }

    private void set_panel_position() {
        switch (this.panel_position) {
            case Budgie.PanelPosition.LEFT:
                this.title_label.angle = 90;
                this.applet_container.orientation = Gtk.Orientation.VERTICAL;
                this.button_box.orientation = Gtk.Orientation.VERTICAL;
                this.title_label.margin_start  = 0;
                this.title_label.margin_end    = 0;
                this.title_label.margin_top    = TITLE_BUTTONS_SPACING;
                this.title_label.margin_bottom = TITLE_BUTTONS_SPACING;
                break;
            case Budgie.PanelPosition.RIGHT:
                this.title_label.angle = 270;
                this.applet_container.orientation = Gtk.Orientation.VERTICAL;
                this.button_box.orientation = Gtk.Orientation.VERTICAL;
                this.title_label.margin_start  = 0;
                this.title_label.margin_end    = 0;
                this.title_label.margin_top    = TITLE_BUTTONS_SPACING;
                this.title_label.margin_bottom = TITLE_BUTTONS_SPACING;
                break;
            default:
                this.title_label.angle = 0;
                this.applet_container.orientation = Gtk.Orientation.HORIZONTAL;
                this.button_box.orientation = Gtk.Orientation.HORIZONTAL;
                this.title_label.margin_start  = TITLE_BUTTONS_SPACING;
                this.title_label.margin_end    = TITLE_BUTTONS_SPACING;
                this.title_label.margin_top    = 0;
                this.title_label.margin_bottom = 0;
                break;
        }
    }

    private void set_maximize_button_image() {
        if(this.is_active_window_maximized) {
            this.get_style_context().add_class("maximized");
            this.maximize_button.image = this.restore_image;
        } else {
            this.get_style_context().remove_class("maximized");
            this.maximize_button.image = this.maximize_image;
        }
    }

    void on_blacklist_settings_change(string key) {
        if (key == "blacklist-apps") {
            string[] blacklist_apps = blacklist_settings.get_strv(key);
            this.force_hide = this.title_bar_manager.check_valid_app(blacklist_apps);
        }
        this.update_visibility();
    }

    void on_settings_change(string key) {
        if (key == "size") {
            this.title_label.set_max_width_chars(settings.get_int(key));
            this.title_label.set_width_chars(settings.get_int(key));
        } else if (key == "visibility") {
            int visibility = settings.get_int(key);
            switch (visibility) {
                case VISIBILITY_TITLE_BUTTONS:
                    this.is_buttons_visible = true;
                    this.is_title_visible = true;
                    break;
                case VISIBILITY_TITLE:
                    this.is_buttons_visible = false;
                    this.is_title_visible = true;
                    break;
                case VISIBILITY_BUTTONS:
                    this.is_buttons_visible = true;
                    this.is_title_visible = false;
                    break;
            }
        } else if (key == "theme-buttons") {
            this.theme_buttons = settings.get_boolean(key);
            this.set_css_styles();
        } else if (key == "theme-title") {
            this.theme_title = settings.get_boolean(key);
            this.set_css_styles();
        } else if (key == "title-alignment") {
            this.title_alignment = settings.get_int(key);
            this.set_title_alignment();
        }
        this.update_visibility();
    }

    void update_visibility() {
        bool hide_for_csd = this.is_active_window_csd && this.settings.get_boolean("hide-for-csd");
        bool hide_for_unmaximized = !this.is_active_window_maximized && this.settings.get_boolean("hide-for-unmaximized");

        /*if (!this.is_buttons_visible) {
            message("not is buttons visble");
        }

        if (this.is_active_window_csd) {
            message("this is a csd window");
        }

        if (this.settings.get_boolean("hide-for-csd")) {
            message("settings hide csd");
        }

        if (this.settings.get_boolean("hide-for-unmaximized")) {
            message("settings hide for unmax");
        }

        if (hide_for_csd) {
            message("hide for csd");
        }

        if (hide_for_unmaximized) {
            message("hide for unmaximised");
        }
        */

        /*if( !this.is_buttons_visible || hide_for_unmaximized || hide_for_csd ) {
            this.maximize_button.hide();
            this.minimize_button.hide();
            this.close_button.hide();
            this.applet_container.hide();
        } else {
            this.maximize_button.show();
            this.minimize_button.show();
            this.close_button.show();
            this.applet_container.show();
        }*/

        if(!this.is_title_visible || hide_for_csd || hide_for_unmaximized || force_hide) {
            this.title_label.hide();
        } else {
            this.title_label.show();
        }

        if( !this.is_buttons_visible || hide_for_unmaximized || hide_for_csd || force_hide) {
            //message("lets hide all");
            this.maximize_button.hide();
            this.minimize_button.hide();
            this.close_button.hide();
            //this.applet_container.hide();
        } else {
            //message("lets show buttons");
            this.maximize_button.show();
            this.minimize_button.show();
            this.close_button.show();
            //this.applet_container.show();
        }

        Gtk.drag_source_unset(this);
        if (this.is_active_window_maximized) {
            Gtk.drag_source_set(this, Gdk.ModifierType.BUTTON1_MASK, target_list, Gdk.DragAction.MOVE);
        }

        queue_resize();
    }

    private void on_drag_end(Gtk.Widget widget, Gdk.DragContext context) {
        this.title_bar_manager.toggle_maximize_active_window();
    }

    void on_wm_settings_changed(string key){
        if(key != "button-style")
            return;

        string button_style = wm_settings.get_string(key);
        if (button_style == "traditional") {
            this.applet_container.reorder_child (this.title_box,  0);
            this.applet_container.reorder_child (this.button_box, 1);
            this.button_box.reorder_child (this.minimize_button, 0);
            this.button_box.reorder_child (this.maximize_button, 1);
            this.button_box.reorder_child (this.close_button,    2);
        } else if(button_style == "left") {
            this.applet_container.reorder_child (this.button_box, 0);
            this.applet_container.reorder_child (this.title_box,  1);
            this.button_box.reorder_child (this.close_button,    0);
            this.button_box.reorder_child (this.maximize_button, 1);
            this.button_box.reorder_child (this.minimize_button, 2);
        }
    }

    /**
     * Update the tasklist orientation to match the panel direction
     */
    public override void panel_position_changed(Budgie.PanelPosition position)
    {
        this.panel_position = position;
        this.set_panel_position();
        this.set_title_alignment();
    }

    public override bool supports_settings() {
        return true;
    }

    public override Gtk.Widget? get_settings_ui()
    {
        return new AppletSettings(this.get_applet_settings(uuid));
    }
}

[GtkTemplate (ui = "/net/milgar/budgie-pixel-saver/settings.ui")]
public class AppletSettings : Gtk.Box
{
    Settings? settings = null;

    [GtkChild]
    private Gtk.SpinButton? spinbutton_length;

    [GtkChild]
    private Gtk.ComboBox? combobox_visibility;

    [GtkChild]
    private Gtk.Switch? switch_csd;

    [GtkChild]
    private Gtk.Switch? switch_unmaximized;

    [GtkChild]
    private Gtk.Switch? switch_theme_buttons;

    [GtkChild]
    private Gtk.Switch? switch_theme_title;

    [GtkChild]
    private Gtk.ComboBox? combobox_title_alignment;

    public AppletSettings(Settings? settings)
    {
        this.settings = settings;

        this.settings.bind("size", spinbutton_length, "value", SettingsBindFlags.DEFAULT);
        this.settings.bind("visibility", combobox_visibility, "active", SettingsBindFlags.DEFAULT);
        this.settings.bind("hide-for-csd", switch_csd, "active", SettingsBindFlags.DEFAULT);
        this.settings.bind("hide-for-unmaximized", switch_unmaximized, "active", SettingsBindFlags.DEFAULT);
        this.settings.bind("theme-buttons", switch_theme_buttons, "active", SettingsBindFlags.DEFAULT);
        this.settings.bind("theme-title", switch_theme_title, "active", SettingsBindFlags.DEFAULT);
        this.settings.bind("title-alignment", combobox_title_alignment, "active", SettingsBindFlags.DEFAULT);
    }
}

}

[ModuleInit]
public void peas_register_types(TypeModule module)
{
    // boilerplate - all modules need this
    var objmodule = module as Peas.ObjectModule;
    objmodule.register_extension_type(typeof(Budgie.Plugin), typeof(PixelSaver.Plugin));
}
