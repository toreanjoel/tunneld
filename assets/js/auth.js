/**
 * WebAuthnHook provides WebAuthn login and registration functionality for LiveView hooks.
 * It handles:
 * 1. Credential creation (`navigator.credentials.create`) for registration.
 * 2. Credential assertion (`navigator.credentials.get`) for login.
 * 3. Encoding/decoding of base64url and ArrayBuffer for WebAuthn compatibility.
 */
export default {
  /**
   * Mounted hook called when the LiveView element is attached to the DOM.
   * Registers event handlers for starting WebAuthn login and registration.
   */
  mounted() {
    console.log("WebAuthnHook mounted");

    /**
     * Triggered when WebAuthn login is initiated.
     * Converts the challenge and credential ID from base64url to ArrayBuffer
     * and invokes the WebAuthn login (`navigator.credentials.get`).
     *
     * @param {Object} param
     * @param {PublicKeyCredentialRequestOptions} param.publicKeyOptions - Options for WebAuthn login.
     */
    this.handleEvent("start_webauthn_login", async ({ publicKeyOptions }) => {
      try {
        // Convert challenge from base64url to Uint8Array
        publicKeyOptions.challenge = this.base64URLToBuffer(
          publicKeyOptions.challenge
        );

        // Convert all credential IDs in allowCredentials
        if (publicKeyOptions.allowCredentials) {
          publicKeyOptions.allowCredentials =
            publicKeyOptions.allowCredentials.map((cred) => ({
              ...cred,
              id: this.base64URLToBuffer(cred.id),
            }));
        }

        const assertion = await navigator.credentials.get({
          publicKey: publicKeyOptions,
        });

        // Send login result back to LiveView
        this.pushEvent("webauthn_login_complete", {
          id: assertion.id,
          rawId: this.bufferToBase64URL(assertion.rawId),
          type: assertion.type,
          response: {
            authenticatorData: this.bufferToBase64URL(
              assertion.response.authenticatorData
            ),
            clientDataJSON: this.bufferToBase64URL(
              assertion.response.clientDataJSON
            ),
            signature: this.bufferToBase64URL(assertion.response.signature),
            userHandle: this.bufferToBase64URL(assertion.response.userHandle),
          },
        });
      } catch (err) {
        this.pushEvent("webauthn_login_error", { error: "There was a error. Please contact the administrator." });
      }
    });

    /**
     * Triggered when WebAuthn registration is initiated.
     * Converts challenge and user ID from base64url to ArrayBuffer,
     * then initiates credential creation via `navigator.credentials.create`.
     *
     * @param {Object} param
     * @param {PublicKeyCredentialCreationOptions} param.publicKeyOptions - Options for WebAuthn registration.
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

  /**
   * Converts a base64url-encoded string to a Uint8Array.
   *
   * @param {string} base64URL - The base64url-encoded string.
   * @returns {Uint8Array} The decoded byte array.
   */
  base64URLToBuffer(base64URL) {
    const base64 = base64URL.replace(/-/g, "+").replace(/_/g, "/");
    const padLen = (4 - (base64.length % 4)) % 4;
    return Uint8Array.from(
      atob(base64.padEnd(base64.length + padLen, "=")),
      (c) => c.charCodeAt(0)
    );
  },

  /**
   * Converts an ArrayBuffer or Uint8Array into a base64url-encoded string.
   *
   * @param {ArrayBuffer | Uint8Array} buffer - The buffer to encode.
   * @returns {string} The base64url-encoded result.
   */
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
