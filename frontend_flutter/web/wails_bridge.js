(() => {
  let nextSubscriptionId = 1;
  const subscriptions = new Map();

  window.antWailsBridge = {
    async invoke(method, argumentsJson) {
      try {
        const app = window.go && window.go.main && window.go.main.App;
        const action = app && app[method];
        if (typeof action !== 'function') {
          throw new Error(`Wails method not found: ${method}`);
        }
        const args = JSON.parse(argumentsJson);
        const value = await action(...args);
        return JSON.stringify({ value: value === undefined ? null : value });
      } catch (error) {
        return JSON.stringify({ error: String(error) });
      }
    },
    openExternal(url) {
      const openUrl = window.runtime && window.runtime.BrowserOpenURL;
      if (typeof openUrl === 'function') {
        openUrl(url);
      } else {
        window.open(url, '_blank', 'noopener,noreferrer');
      }
    },
    subscribe(eventName, callback) {
      const eventsOn = window.runtime && window.runtime.EventsOn;
      if (typeof eventsOn !== 'function') return 0;
      const unsubscribe = eventsOn(eventName, (...args) => callback(JSON.stringify(args)));
      const id = nextSubscriptionId++;
      subscriptions.set(id, unsubscribe);
      return id;
    },
    unsubscribe(id) {
      const unsubscribe = subscriptions.get(id);
      if (typeof unsubscribe === 'function') unsubscribe();
      subscriptions.delete(id);
    },
    windowHide() {
      window.runtime && window.runtime.WindowHide && window.runtime.WindowHide();
    },
    windowMinimise() {
      window.runtime && window.runtime.WindowMinimise && window.runtime.WindowMinimise();
    },
    quit() {
      window.runtime && window.runtime.Quit && window.runtime.Quit();
    },
    async platform() {
      const environment = window.runtime && window.runtime.Environment
        ? await window.runtime.Environment()
        : { platform: 'windows' };
      return environment && environment.platform ? environment.platform : 'windows';
    },
    storageGet(key) {
      try {
        return window.localStorage.getItem(key) || '';
      } catch (_) {
        return '';
      }
    },
    storageSet(key, value) {
      try {
        window.localStorage.setItem(key, value);
      } catch (_) {}
    },
    storageRemove(key) {
      try {
        window.localStorage.removeItem(key);
      } catch (_) {}
    },
  };
})();
