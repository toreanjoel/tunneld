/**
 * WebAuthnHook provides WebAuthn registration functionality for LiveView hooks.
 * Login verification is not yet implemented securely — do not add login
 * until cryptographic signature verification is in place.
 */
export default {
  mounted() {
    console.log("WebAuthnHook mounted");

    /**
     * Triggered when WebAuthn registration is initiated.
     */
    this.handleEvent("start_webauthn", async ({ publicKeyOptions }) => {
      console.log("Received WebAuthn event:", publicKeyOptions);

      try {
        publicKeyOptions.challenge = this.base64URLToBuffer(
          publicKeyOptions.challenge
        );
        publicKeyOptions.user.id = this.base64URLToBuffer(
          publicKeyOptions.user.id
        );

        const credential = await navigator.credentials.create({
          publicKey: publicKeyOptions,
        });

        this.pushEvent("webauthn_register_complete", {
          id: credential.id,
          rawId: this.bufferToBase64URL(credential.rawId),
          type: credential.type,
          response: {
            attestationObject: this.bufferToBase64URL(
              credential.response.attestationObject
            ),
            clientDataJSON: this.bufferToBase64URL(
              credential.response.clientDataJSON
            ),
          },
        });
      } catch (err) {
        this.pushEvent("webauthn_register_error", { error: "There was a error. Please contact the administrator." });
      }
    });
  },

  base64URLToBuffer(base64URL) {
    const base64 = base64URL.replace(/-/g, "+").replace(/_/g, "/");
    const padLen = (4 - (base64.length % 4)) % 4;
    return Uint8Array.from(
      atob(base64.padEnd(base64.length + padLen, "=")),
      (c) => c.charCodeAt(0)
    );
  },

  bufferToBase64URL(buffer) {
    const bytes = new Uint8Array(buffer);
    let binary = "";
    for (let i = 0; i < bytes.byteLength; i++) {
      binary += String.fromCharCode(bytes[i]);
    }
    const base64 = btoa(binary);
    return base64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  },
};