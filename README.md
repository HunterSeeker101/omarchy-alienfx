# AlienFX Lighting

A Quickshell bar widget for setting the RGB lighting zones and brightness on supported Alienware Aurora desktops. It delegates hardware writes to the separate, fully open-source [alienfx-lightd companion](https://github.com/hunterseeker101/alienfx-lightd), which includes the `alienfx-gui` client. Both repositories are MIT licensed and free.

## Support this project

The plugin and companion are free forever. Donations are optional through [the support page](https://ko-fi.com/hunterseeker101) or [DR's Mad Lab on Patreon](https://www.patreon.com/cw/DRsMadLab). If you don't donate, you still get everything.

## Hardware and requirements

Verified on an Alienware Aurora R7 desktop. Aurora R6 is expected to work but is untested; reports are welcome. This project is not for Alienware laptops or USB/HID AlienFX keyboards; see the existing “AlienFX” listing by 3mrgnc3 for that hardware.

Requirements:

- Omarchy with Quickshell.
- The [companion daemon and client](https://github.com/hunterseeker101/alienfx-lightd) installed and the daemon started.
- Linux with the `acpi_call` module and `/proc/acpi/call` available.

Install the companion first using its documented `sudo ./install.sh --user YOUR_LOGIN` command. That installs files but leaves the service stopped and disabled; start it with `sudo systemctl start alienfx-lightd.service`. Then install this plugin directory to `~/.config/omarchy/plugins/io.github.hunterseeker101.alienfx/` and enable it with:

```sh
omarchy plugin enable io.github.hunterseeker101.alienfx
```

## Controls and state

The widget offers two color zones and global brightness. Zone A sends `left`, Zone B sends `right`; selecting a zone preserves the other zone and current brightness. Brightness ranges from 0 to 15 and reapplies the colors held in widget state.

The daemon is write-only: it does not report current hardware state, and the old sysfs interface on this generation reports stale values. The widget stores its last requested values in `$XDG_STATE_HOME/omarchy-alienfx/state.json` (usually `~/.local/state/omarchy-alienfx/state.json`). The initial seed is Zone A `#0088FF`, Zone B `#FF00AA`, brightness 10. If lighting changes outside the widget or the firmware resets it, displayed state can drift; the next request reapplies the widget's stored values for the zones it sends.

## Caveats

- Firmware effectively has 4-bit color channels (16 levels, 0–15), although the client request uses 0–255 values.
- Blue can overpower green at high levels on the verified Aurora R7; adjust colors by eye.
- The power-button light is not reliably controlled and is unsupported by this widget.
- There is no fan control.
- This widget does not access hardware directly. The privileged companion validates requests and issues a fixed ACPI lighting sequence; see its [security model](https://github.com/hunterseeker101/alienfx-lightd#security-model).
- Removing the plugin does not uninstall or stop the companion. Follow the companion's uninstall instructions separately.

## License

MIT; see [LICENSE](LICENSE).

## Support this project

This project is free forever. Donations are optional through [the support page](https://ko-fi.com/hunterseeker101) or [DR's Mad Lab on Patreon](https://www.patreon.com/cw/DRsMadLab). If you don't donate, you still get everything.
