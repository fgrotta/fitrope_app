library;

/// Svuota la sessione Firebase Auth persistita, **prima** che l'istanza di Auth
/// nasca.
///
/// Serve solo in modalità emulatore: se una sessione è già in IndexedDB, l'SDK
/// la ripristina e ne rinnova il token su `securetoken.googleapis.com` — cioè
/// sul progetto di PRODUZIONE — e da lì auth resta legata a quello, senza
/// errori e senza il banner rosso dell'SDK.
///
/// Va chiamata prima di toccare `FirebaseAuth.instance`: dopo è troppo tardi,
/// perché il ripristino parte alla creazione dell'istanza e `signOut()` è a sua
/// volta un uso di auth (che tra l'altro impedisce a `useAuthEmulator` di
/// agganciarsi, dovendo precedere qualunque operazione).
export 'clear_auth_persistence_stub.dart'
    if (dart.library.js_interop) 'clear_auth_persistence_web.dart';
