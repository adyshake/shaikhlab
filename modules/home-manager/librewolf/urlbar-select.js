// Privileged chrome script: select the address bar on the start page.
// Loaded from librewolf.cfg after general.config.sandbox_enabled is false.
(() => {
  const START = "https://start.adnanshaikh.com";
  const LOG = "/tmp/shaikhlab-urlbar.log";

  const log = msg => {
    try {
      const Cc = Components.classes;
      const Ci = Components.interfaces;
      const file = Cc["@mozilla.org/file/local;1"].createInstance(Ci.nsIFile);
      file.initWithPath(LOG);
      const stream = Cc["@mozilla.org/network/file-output-stream;1"].createInstance(
        Ci.nsIFileOutputStream
      );
      stream.init(file, 0x02 | 0x08 | 0x10, 0o644, 0);
      const line = `${new Date().toISOString()} ${msg}\n`;
      stream.write(line, line.length);
      stream.close();
    } catch {
      // Ignore logging failures.
    }
  };

  const isStartURI = win => {
    try {
      const spec = win.gBrowser.currentURI.spec;
      return spec === START || spec.startsWith(`${START}/`) || spec.startsWith(`${START}?`);
    } catch {
      return false;
    }
  };

  const userIsTyping = win => {
    const typed = win.gURLBar?.userTypedValue;
    return Boolean(typed) && !typed.startsWith(START);
  };

  const selectUrlbar = win => {
    try {
      if (!win.gURLBar || userIsTyping(win) || !isStartURI(win)) {
        return false;
      }
      if (typeof win.focusAndSelectUrlBar === "function") {
        win.focusAndSelectUrlBar();
      }
      win.gURLBar.focus();
      win.gURLBar.select();
      const input =
        win.gURLBar.inputField || win.document.getElementById("urlbar-input");
      if (input) {
        input.focus();
        input.select();
        if (typeof input.setSelectionRange === "function") {
          input.setSelectionRange(0, input.value.length);
        }
      }
      return true;
    } catch (e) {
      log(`select failed: ${e}`);
      return false;
    }
  };

  const scheduleSelect = win => {
    let n = 0;
    const tick = () => {
      if (userIsTyping(win) || win.closed) {
        return;
      }
      selectUrlbar(win);
      if (++n < 25) {
        win.setTimeout(tick, 80);
      }
    };
    tick();
  };

  const hookWindow = win => {
    if (!win || win.closed || win.__shaikhlabUrlbarSelect) {
      return;
    }
    if (!win.gBrowser || !win.gURLBar) {
      return;
    }
    win.__shaikhlabUrlbarSelect = true;
    log("hooked browser window");

    win.gBrowser.tabContainer.addEventListener("TabSelect", () =>
      scheduleSelect(win)
    );
    win.gBrowser.tabContainer.addEventListener("TabOpen", () =>
      scheduleSelect(win)
    );
    win.gBrowser.addTabsProgressListener({
      onLocationChange(browser, webProgress, _request, location) {
        if (!webProgress.isTopLevel) {
          return;
        }
        if (browser !== win.gBrowser.selectedBrowser) {
          return;
        }
        if (location && location.spec && location.spec.startsWith(START)) {
          scheduleSelect(win);
        }
      },
    });
    scheduleSelect(win);
  };

  const Services =
    globalThis.Services ||
    ChromeUtils.importESModule("resource://gre/modules/Services.sys.mjs")
      .Services;

  log("urlbar-select loaded");

  for (const win of Services.wm.getEnumerator("navigator:browser")) {
    hookWindow(win);
  }

  Services.obs.addObserver(subject => {
    subject.addEventListener(
      "load",
      () => {
        try {
          if (
            subject.document.documentElement.getAttribute("windowtype") ===
            "navigator:browser"
          ) {
            hookWindow(subject);
          }
        } catch (e) {
          log(`window load: ${e}`);
        }
      },
      {once: true}
    );
  }, "chrome-document-global-created");

  Services.obs.addObserver(win => {
    hookWindow(win);
  }, "browser-delayed-startup-finished");
})();
