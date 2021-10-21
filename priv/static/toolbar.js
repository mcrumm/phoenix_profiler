(function() {
  let toolbar = document.querySelector(".phxweb-toolbar")
  let toggleHidden = function() {
    toolbar.classList.toggle("hidden")
  }

  let showButton = toolbar.querySelector("button.show-button")
  showButton.addEventListener("click", toggleHidden)

  let hideButton = toolbar.querySelector("button.hide-button")
  hideButton.addEventListener("click", toggleHidden)
})();
