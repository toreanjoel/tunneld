let Hooks = {}

/**
 * Listen and request access trigger for the fullscreen click event
 */
Hooks.FullscreenIframe = {
  mounted() {
    document.getElementById('fullscreen-btn').addEventListener('click', () => {
      const iframe = document.querySelector('iframe');
      if (iframe && iframe.requestFullscreen) {
        iframe.requestFullscreen();
      }
    });
    
  }
}

export default Hooks;
