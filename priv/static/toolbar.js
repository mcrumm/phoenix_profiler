const PHX_TOOLBAR_LV_CONTROL = {
  mounted(){
    this.handleEvent("enable-debug", ({}) => {
      window.liveSocket.enableDebug()
      this.pushEvent("lv-status", {isDebugEnabled: window.liveSocket.isDebugEnabled()})
    })

    this.handleEvent("disable-debug", ({}) => {
      window.liveSocket.disableDebug()
      this.pushEvent("lv-status", {isDebugEnabled: window.liveSocket.isDebugEnabled()})
    })

    this.pushEvent("lv-status", {isDebugEnabled: window.liveSocket.isDebugEnabled()})
  }
}

window.addEventListener('DOMContentLoaded', (event) => {
  window.liveSocket.hooks.PHX_TOOLBAR_LV_CONTROL = PHX_TOOLBAR_LV_CONTROL
})
