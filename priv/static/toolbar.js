const liveSocket = () => window.PHXWEB_TOOLBAR_LIVE_SOCKET

const PHXWEB_TOOLBAR_LV_PROXY = {
  mounted(){
    this.handleEvent("enable-debug", ({}) => {
      liveSocket().enableDebug()
      this.pushStatus()
    })

    this.handleEvent("disable-debug", ({}) => {
      liveSocket().disableDebug()
      this.pushStatus()
    })

    this.pushStatus()
  },
  pushStatus() {
    this.pushEvent("lv-status", {
      isConnected: liveSocket().isConnected(),
      isDebugEnabled: liveSocket().isDebugEnabled()
    })
  }
}

window.addEventListener('DOMContentLoaded', (event) => {
  liveSocket().hooks.PHXWEB_TOOLBAR_LV_PROXY = PHXWEB_TOOLBAR_LV_PROXY
})
