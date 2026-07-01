import * as admin from "firebase-admin";

// Inizializza l'app admin una sola volta. Il guard evita l'errore
// "default app already exists" se in futuro un'altra function la inizializza.
if (admin.apps.length === 0) {
  admin.initializeApp();
}

export const db = admin.firestore();
export { admin };
