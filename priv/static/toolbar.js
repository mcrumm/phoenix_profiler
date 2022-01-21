(function() {
  var SHOW = "phxprof-toolbar-show";

  // Browser
  // Copyright (c) 2018 Chris McCord
  // https://github.com/phoenixframework/phoenix_live_view/blob/2ea98193420d236cbd5797e0cd258233c4dff5a7/assets/js/phoenix_live_view/browser.js
  var Browser = {
    setLocal(localStorage, namespace, subkey, value) {
      var key = this.localKey(namespace, subkey)
      localStorage.setItem(key, JSON.stringify(value))
      return value
    },
    getLocal(localStorage, namespace, subkey, defaultVal) {
      var value = JSON.parse(localStorage.getItem(this.localKey(namespace, subkey)))
      return value === null ? defaultVal : value
    },
    localKey(namespace, subkey) {
      return `${namespace}-${subkey}`
    },
    show(localStorage) {
      this.setLocal(localStorage, window.location.host, SHOW, true)
      toolbar.classList.remove("miniaturized")
    },
    hide(localStorage) {
      this.setLocal(localStorage, window.location.host, SHOW, false)
      toolbar.classList.add("miniaturized")
    },
    showOrHide(localStorage) {
      (this.getLocal(localStorage, window.location.host, SHOW, true)) ? this.show(localStorage): this.hide(localStorage)
    }
  };

  var localStorage = window.localStorage;

  var showToolbar = function() { Browser.show(localStorage); };
  var hideToolbar = function() { Browser.hide(localStorage); };

  var toolbar = document.querySelector(".phxprof-toolbar");

  var showButton = toolbar.querySelector("button.show-button");
  showButton.addEventListener("click", showToolbar);

  var hideButton = toolbar.querySelector("button.hide-button");
  hideButton.addEventListener("click", hideToolbar);

  Browser.showOrHide(localStorage);
})();
