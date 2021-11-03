(function() {
  const SHOW = "phxweb-profiler-show"

  let Browser = {
    setLocal(localStorage, namespace, subkey, value) {
      let key = this.localKey(namespace, subkey)
      localStorage.setItem(key, JSON.stringify(value))
      return value
    },
    getLocal(localStorage, namespace, subkey, defaultVal) {
      let value = JSON.parse(localStorage.getItem(this.localKey(namespace, subkey)))
      return value === null ? defaultVal : value
    },
    localKey(namespace, subkey) {
      return `${namespace}-${subkey}`
    },
    show(localStorage) {
      this.setLocal(localStorage, window.location.host, SHOW, true)
      toolbar.classList.remove("hidden")
    },
    hide(localStorage) {
      this.setLocal(localStorage, window.location.host, SHOW, false)
      toolbar.classList.add("hidden")
    },
    showOrHide(localStorage) {
      (this.getLocal(localStorage, window.location.host, SHOW, true)) ? this.show(localStorage) : this.hide(localStorage)
    }
  }
  let browser_default = Browser

  let localStorage = window.localStorage
  let toolbar = document.querySelector(".phxweb-toolbar")

  let showButton = toolbar.querySelector("button.show-button")
  showButton.addEventListener("click", () => browser_default.show(localStorage))

  let hideButton = toolbar.querySelector("button.hide-button")
  hideButton.addEventListener("click", () => browser_default.hide(localStorage))

  browser_default.showOrHide(localStorage)
})();
