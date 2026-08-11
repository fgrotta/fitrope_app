// Config Jest per i test di INTEGRAZIONE su Firebase Emulator Suite
// (categoria C del piano). Non girano con `npm test`: vanno lanciati con
// `npm run test:integration`, che avvia gli emulatori via `emulators:exec`.
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  testMatch: ["**/__integration__/**/*.test.ts"],
  // I test condividono gli emulatori: serializzati per evitare interferenze.
  maxWorkers: 1,
  // Le transazioni reali sull'emulatore sono lente rispetto agli unit test.
  testTimeout: 30000,
};
