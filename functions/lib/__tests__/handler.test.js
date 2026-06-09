"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const handler_1 = require("../handler");
const https_1 = require("firebase-functions/v2/https");
// Silenzia i log durante i test
jest.mock("firebase-functions", () => ({
    logger: {
        info: jest.fn(),
        error: jest.fn(),
        warn: jest.fn(),
    },
}));
const API_KEY = "test-api-key";
describe("sendOneSignalNotificationHandler", () => {
    let fetchMock;
    beforeEach(() => {
        fetchMock = jest.fn();
        global.fetch = fetchMock;
    });
    afterEach(() => {
        jest.clearAllMocks();
    });
    function mockOneSignalSuccess(data = { id: "notif-123" }) {
        fetchMock.mockResolvedValue({
            ok: true,
            status: 200,
            json: async () => data,
        });
    }
    function mockOneSignalError(status, errors) {
        fetchMock.mockResolvedValue({
            ok: false,
            status,
            json: async () => ({ errors }),
        });
    }
    describe("Autenticazione", () => {
        test("rifiuta richieste non autenticate", async () => {
            const request = {
                auth: null,
                data: { include_aliases: { external_id: ["u1"] } },
            };
            await expect((0, handler_1.sendOneSignalNotificationHandler)(request, API_KEY)).rejects.toThrow(https_1.HttpsError);
            await expect((0, handler_1.sendOneSignalNotificationHandler)(request, API_KEY)).rejects.toMatchObject({ code: "unauthenticated" });
            expect(fetchMock).not.toHaveBeenCalled();
        });
        test("accetta richieste autenticate", async () => {
            mockOneSignalSuccess();
            const request = {
                auth: { uid: "user-1" },
                data: { include_aliases: { external_id: ["u1"] } },
            };
            const result = await (0, handler_1.sendOneSignalNotificationHandler)(request, API_KEY);
            expect(result).toEqual({ id: "notif-123" });
            expect(fetchMock).toHaveBeenCalledTimes(1);
        });
    });
    describe("Validazione payload", () => {
        test("rifiuta payload null", async () => {
            const request = {
                auth: { uid: "user-1" },
                data: null,
            };
            await expect((0, handler_1.sendOneSignalNotificationHandler)(request, API_KEY)).rejects.toMatchObject({ code: "invalid-argument" });
            expect(fetchMock).not.toHaveBeenCalled();
        });
        test("rifiuta payload stringa", async () => {
            const request = {
                auth: { uid: "user-1" },
                data: "not-an-object",
            };
            await expect((0, handler_1.sendOneSignalNotificationHandler)(request, API_KEY)).rejects.toMatchObject({ code: "invalid-argument" });
            expect(fetchMock).not.toHaveBeenCalled();
        });
        test("accetta payload oggetto vuoto", async () => {
            mockOneSignalSuccess();
            const request = {
                auth: { uid: "user-1" },
                data: {},
            };
            await (0, handler_1.sendOneSignalNotificationHandler)(request, API_KEY);
            expect(fetchMock).toHaveBeenCalledTimes(1);
        });
    });
    describe("Inoltro a OneSignal", () => {
        test("inietta app_id server-side anche se il client non lo fornisce", async () => {
            mockOneSignalSuccess();
            const request = {
                auth: { uid: "user-1" },
                data: { include_aliases: { external_id: ["u1"] } },
            };
            await (0, handler_1.sendOneSignalNotificationHandler)(request, API_KEY);
            const sentBody = JSON.parse(fetchMock.mock.calls[0][1].body);
            expect(sentBody.app_id).toBe(handler_1.ONESIGNAL_APP_ID);
        });
        test("sovrascrive app_id se il client tenta di inviarne uno diverso", async () => {
            mockOneSignalSuccess();
            const request = {
                auth: { uid: "user-1" },
                data: { app_id: "malicious-app-id", include_aliases: { external_id: ["u1"] } },
            };
            await (0, handler_1.sendOneSignalNotificationHandler)(request, API_KEY);
            const sentBody = JSON.parse(fetchMock.mock.calls[0][1].body);
            expect(sentBody.app_id).toBe(handler_1.ONESIGNAL_APP_ID);
        });
        test("usa l'API key fornita nell'header Authorization", async () => {
            mockOneSignalSuccess();
            const request = {
                auth: { uid: "user-1" },
                data: { include_aliases: { external_id: ["u1"] } },
            };
            await (0, handler_1.sendOneSignalNotificationHandler)(request, API_KEY);
            const headers = fetchMock.mock.calls[0][1].headers;
            expect(headers.Authorization).toBe(`Key ${API_KEY}`);
        });
        test("chiama il corretto endpoint OneSignal", async () => {
            mockOneSignalSuccess();
            const request = {
                auth: { uid: "user-1" },
                data: { include_aliases: { external_id: ["u1"] } },
            };
            await (0, handler_1.sendOneSignalNotificationHandler)(request, API_KEY);
            expect(fetchMock).toHaveBeenCalledWith(handler_1.ONESIGNAL_API_URL, expect.objectContaining({ method: "POST" }));
        });
        test("inoltra tutti i campi del payload", async () => {
            mockOneSignalSuccess();
            const request = {
                auth: { uid: "user-1" },
                data: {
                    include_aliases: { external_id: ["u1", "u2"] },
                    target_channel: "email",
                    email_subject: "Test",
                    email_body: "<html>body</html>",
                    send_after: "2026-05-01T19:00:00.000Z",
                },
            };
            await (0, handler_1.sendOneSignalNotificationHandler)(request, API_KEY);
            const sentBody = JSON.parse(fetchMock.mock.calls[0][1].body);
            expect(sentBody.include_aliases).toEqual({ external_id: ["u1", "u2"] });
            expect(sentBody.target_channel).toBe("email");
            expect(sentBody.email_subject).toBe("Test");
            expect(sentBody.email_body).toBe("<html>body</html>");
            expect(sentBody.send_after).toBe("2026-05-01T19:00:00.000Z");
        });
    });
    describe("Gestione risposte OneSignal", () => {
        test("ritorna il body della risposta in caso di successo", async () => {
            mockOneSignalSuccess({ id: "abc-123", recipients: 5 });
            const request = {
                auth: { uid: "user-1" },
                data: { include_aliases: { external_id: ["u1"] } },
            };
            const result = await (0, handler_1.sendOneSignalNotificationHandler)(request, API_KEY);
            expect(result).toEqual({ id: "abc-123", recipients: 5 });
        });
        test("lancia HttpsError internal quando OneSignal risponde con errore", async () => {
            mockOneSignalError(400, ["Invalid app_id"]);
            const request = {
                auth: { uid: "user-1" },
                data: { include_aliases: { external_id: ["u1"] } },
            };
            await expect((0, handler_1.sendOneSignalNotificationHandler)(request, API_KEY)).rejects.toMatchObject({
                code: "internal",
                message: expect.stringContaining("Invalid app_id"),
            });
        });
        test("gestisce risposta errore senza campo errors", async () => {
            fetchMock.mockResolvedValue({
                ok: false,
                status: 500,
                json: async () => ({}),
            });
            const request = {
                auth: { uid: "user-1" },
                data: { include_aliases: { external_id: ["u1"] } },
            };
            await expect((0, handler_1.sendOneSignalNotificationHandler)(request, API_KEY)).rejects.toMatchObject({
                code: "internal",
                message: "Errore OneSignal",
            });
        });
        test("lancia HttpsError unavailable se fetch fallisce", async () => {
            fetchMock.mockRejectedValue(new Error("Network error"));
            const request = {
                auth: { uid: "user-1" },
                data: { include_aliases: { external_id: ["u1"] } },
            };
            await expect((0, handler_1.sendOneSignalNotificationHandler)(request, API_KEY)).rejects.toMatchObject({
                code: "unavailable",
                message: "Impossibile contattare OneSignal",
            });
        });
    });
});
describe("ensureOneSignalUserHandler", () => {
    let fetchMock;
    beforeEach(() => {
        fetchMock = jest.fn();
        global.fetch = fetchMock;
    });
    afterEach(() => {
        jest.clearAllMocks();
    });
    function mockFetchResponse(status, data) {
        return {
            ok: status >= 200 && status < 300,
            status,
            json: async () => data,
        };
    }
    describe("Autenticazione e validazione", () => {
        test("rifiuta richieste non autenticate", async () => {
            const request = {
                auth: null,
                data: { externalId: "user-1", email: "test@example.com" },
            };
            await expect((0, handler_1.ensureOneSignalUserHandler)(request, API_KEY)).rejects.toMatchObject({ code: "unauthenticated" });
            expect(fetchMock).not.toHaveBeenCalled();
        });
        test("rifiuta payload senza externalId", async () => {
            const request = {
                auth: { uid: "user-1" },
                data: { email: "test@example.com" },
            };
            await expect((0, handler_1.ensureOneSignalUserHandler)(request, API_KEY)).rejects.toMatchObject({ code: "invalid-argument" });
            expect(fetchMock).not.toHaveBeenCalled();
        });
        test("rifiuta payload null", async () => {
            const request = {
                auth: { uid: "user-1" },
                data: null,
            };
            await expect((0, handler_1.ensureOneSignalUserHandler)(request, API_KEY)).rejects.toMatchObject({ code: "invalid-argument" });
        });
    });
    describe("Creazione utente", () => {
        test("crea un utente con email subscription", async () => {
            fetchMock.mockResolvedValueOnce(mockFetchResponse(200, {
                identity: { external_id: "user-1", onesignal_id: "abc" },
            }));
            const request = {
                auth: { uid: "user-1" },
                data: { externalId: "user-1", email: "test@example.com" },
            };
            const result = await (0, handler_1.ensureOneSignalUserHandler)(request, API_KEY);
            expect(fetchMock).toHaveBeenCalledTimes(1);
            expect(fetchMock).toHaveBeenCalledWith(handler_1.ONESIGNAL_USERS_URL, expect.objectContaining({ method: "POST" }));
            const sentBody = JSON.parse(fetchMock.mock.calls[0][1].body);
            expect(sentBody.identity).toEqual({ external_id: "user-1" });
            expect(sentBody.subscriptions).toEqual([
                { type: "Email", token: "test@example.com", enabled: true },
            ]);
            expect(result).toMatchObject({ identity: { external_id: "user-1" } });
        });
        test("crea un utente senza subscriptions se email mancante", async () => {
            fetchMock.mockResolvedValueOnce(mockFetchResponse(200, { ok: true }));
            const request = {
                auth: { uid: "user-1" },
                data: { externalId: "user-1" },
            };
            await (0, handler_1.ensureOneSignalUserHandler)(request, API_KEY);
            const sentBody = JSON.parse(fetchMock.mock.calls[0][1].body);
            expect(sentBody.subscriptions).toBeUndefined();
        });
        test("usa header Authorization: Key <apiKey>", async () => {
            fetchMock.mockResolvedValueOnce(mockFetchResponse(200, {}));
            const request = {
                auth: { uid: "user-1" },
                data: { externalId: "user-1" },
            };
            await (0, handler_1.ensureOneSignalUserHandler)(request, API_KEY);
            const headers = fetchMock.mock.calls[0][1].headers;
            expect(headers.Authorization).toBe(`Key ${API_KEY}`);
        });
        test("trimma eventuali spazi nell'email", async () => {
            fetchMock.mockResolvedValueOnce(mockFetchResponse(200, {}));
            const request = {
                auth: { uid: "user-1" },
                data: { externalId: "user-1", email: "  test@example.com  " },
            };
            await (0, handler_1.ensureOneSignalUserHandler)(request, API_KEY);
            const sentBody = JSON.parse(fetchMock.mock.calls[0][1].body);
            expect(sentBody.subscriptions[0].token).toBe("test@example.com");
        });
        test("non imposta l'app_id nel body (è nell'URL)", async () => {
            fetchMock.mockResolvedValueOnce(mockFetchResponse(200, {}));
            const request = {
                auth: { uid: "user-1" },
                data: { externalId: "user-1" },
            };
            await (0, handler_1.ensureOneSignalUserHandler)(request, API_KEY);
            const sentBody = JSON.parse(fetchMock.mock.calls[0][1].body);
            expect(sentBody.app_id).toBeUndefined();
            // Verifica che l'URL contenga l'app_id
            expect(fetchMock.mock.calls[0][0]).toContain(handler_1.ONESIGNAL_APP_ID);
        });
    });
    describe("Utente già esistente (409)", () => {
        test("aggiunge l'email subscription se l'utente esiste già", async () => {
            // Prima chiamata: POST /users → 409
            fetchMock.mockResolvedValueOnce(mockFetchResponse(409, {
                errors: ["User with external_id already exists"],
            }));
            // Seconda chiamata: POST /users/by/external_id/.../subscriptions → 200
            fetchMock.mockResolvedValueOnce(mockFetchResponse(200, {
                subscription: { id: "sub-1", type: "Email" },
            }));
            const request = {
                auth: { uid: "user-1" },
                data: { externalId: "user-1", email: "test@example.com" },
            };
            const result = await (0, handler_1.ensureOneSignalUserHandler)(request, API_KEY);
            expect(fetchMock).toHaveBeenCalledTimes(2);
            // La seconda chiamata deve essere all'endpoint subscriptions
            const secondCallUrl = fetchMock.mock.calls[1][0];
            expect(secondCallUrl).toContain("/users/by/external_id/user-1/subscriptions");
            const secondCallBody = JSON.parse(fetchMock.mock.calls[1][1].body);
            expect(secondCallBody.subscription).toEqual({
                type: "Email",
                token: "test@example.com",
                enabled: true,
            });
            expect(result).toMatchObject({ alreadyExisted: true });
        });
        test("accetta 409 anche sull'endpoint subscriptions (email già presente)", async () => {
            fetchMock.mockResolvedValueOnce(mockFetchResponse(409, {})); // users
            fetchMock.mockResolvedValueOnce(mockFetchResponse(409, {})); // subscriptions
            fetchMock.mockResolvedValueOnce(mockFetchResponse(202, { success: true })); // re-enable
            const request = {
                auth: { uid: "user-1" },
                data: { externalId: "user-1", email: "test@example.com" },
            };
            const result = await (0, handler_1.ensureOneSignalUserHandler)(request, API_KEY);
            expect(fetchMock).toHaveBeenCalledTimes(3);
            expect(fetchMock.mock.calls[2][0]).toBe(`${handler_1.ONESIGNAL_SUBSCRIPTIONS_BY_TOKEN_URL}/Email/test%40example.com`);
            expect(JSON.parse(fetchMock.mock.calls[2][1].body)).toEqual({
                subscription: {
                    enabled: true,
                    notification_types: 1,
                },
            });
            expect(result).toMatchObject({ alreadyExisted: true, reenabled: true });
        });
        test("lancia errore se 409 senza email (non può aggiungere subscription)", async () => {
            fetchMock.mockResolvedValueOnce(mockFetchResponse(409, {
                errors: ["already exists"],
            }));
            const request = {
                auth: { uid: "user-1" },
                data: { externalId: "user-1" },
            };
            await expect((0, handler_1.ensureOneSignalUserHandler)(request, API_KEY)).rejects.toMatchObject({ code: "internal" });
            expect(fetchMock).toHaveBeenCalledTimes(1);
        });
        test("encoda correttamente external_id con caratteri speciali", async () => {
            fetchMock.mockResolvedValueOnce(mockFetchResponse(409, {}));
            fetchMock.mockResolvedValueOnce(mockFetchResponse(200, {}));
            const request = {
                auth: { uid: "user-1" },
                data: { externalId: "user with/slash", email: "test@example.com" },
            };
            await (0, handler_1.ensureOneSignalUserHandler)(request, API_KEY);
            const subUrl = fetchMock.mock.calls[1][0];
            expect(subUrl).toContain("user%20with%2Fslash");
        });
    });
    describe("Gestione errori", () => {
        test("lancia HttpsError internal su risposta errore diversa da 409", async () => {
            fetchMock.mockResolvedValueOnce(mockFetchResponse(400, {
                errors: ["Invalid email format"],
            }));
            const request = {
                auth: { uid: "user-1" },
                data: { externalId: "user-1", email: "invalid" },
            };
            await expect((0, handler_1.ensureOneSignalUserHandler)(request, API_KEY)).rejects.toMatchObject({
                code: "internal",
                message: expect.stringContaining("Invalid email"),
            });
        });
        test("lancia HttpsError unavailable se fetch fallisce", async () => {
            fetchMock.mockRejectedValueOnce(new Error("Network down"));
            const request = {
                auth: { uid: "user-1" },
                data: { externalId: "user-1", email: "test@example.com" },
            };
            await expect((0, handler_1.ensureOneSignalUserHandler)(request, API_KEY)).rejects.toMatchObject({ code: "unavailable" });
        });
    });
});
describe("removeOneSignalEmailHandler", () => {
    let fetchMock;
    beforeEach(() => {
        fetchMock = jest.fn();
        global.fetch = fetchMock;
    });
    afterEach(() => {
        jest.clearAllMocks();
    });
    function mockFetchResponse(status, data) {
        return {
            ok: status >= 200 && status < 300,
            status,
            json: async () => data,
        };
    }
    test("rifiuta richieste non autenticate", async () => {
        const request = {
            auth: null,
            data: { email: "test@example.com" },
        };
        await expect((0, handler_1.removeOneSignalEmailHandler)(request, API_KEY)).rejects.toMatchObject({ code: "unauthenticated" });
        expect(fetchMock).not.toHaveBeenCalled();
    });
    test("rifiuta payload senza email", async () => {
        const request = {
            auth: { uid: "user-1" },
            data: {},
        };
        await expect((0, handler_1.removeOneSignalEmailHandler)(request, API_KEY)).rejects.toMatchObject({ code: "invalid-argument" });
        expect(fetchMock).not.toHaveBeenCalled();
    });
    test("considera già rimossa la subscription se l'utente OneSignal non esiste", async () => {
        fetchMock.mockResolvedValueOnce(mockFetchResponse(404, {}));
        const request = {
            auth: { uid: "user-1" },
            data: { email: "test@example.com" },
        };
        const result = await (0, handler_1.removeOneSignalEmailHandler)(request, API_KEY);
        expect(result).toMatchObject({ alreadyRemoved: true, reason: "user_not_found" });
        expect(fetchMock).toHaveBeenCalledTimes(1);
    });
    test("considera già rimossa la subscription se l'email non è presente", async () => {
        fetchMock.mockResolvedValueOnce(mockFetchResponse(200, {
            subscriptions: [
                { id: "sub-push-1", type: "iOSPush", token: "push-token", enabled: true },
            ],
        }));
        const request = {
            auth: { uid: "user-1" },
            data: { email: "test@example.com" },
        };
        const result = await (0, handler_1.removeOneSignalEmailHandler)(request, API_KEY);
        expect(result).toMatchObject({ alreadyRemoved: true, reason: "email_not_found" });
        expect(fetchMock).toHaveBeenCalledTimes(1);
    });
    test("disabilita la subscription email trovata sull'utente autenticato", async () => {
        fetchMock.mockResolvedValueOnce(mockFetchResponse(200, {
            subscriptions: [
                { id: "sub-email-1", type: "Email", token: "test@example.com", enabled: true },
            ],
        }));
        fetchMock.mockResolvedValueOnce(mockFetchResponse(202, { success: true }));
        const request = {
            auth: { uid: "user-1" },
            data: { email: "test@example.com" },
        };
        const result = await (0, handler_1.removeOneSignalEmailHandler)(request, API_KEY);
        expect(fetchMock).toHaveBeenCalledTimes(2);
        expect(fetchMock.mock.calls[0][0]).toBe(`${handler_1.ONESIGNAL_USERS_URL}/by/external_id/user-1`);
        expect(fetchMock.mock.calls[1][0]).toBe(`${handler_1.ONESIGNAL_SUBSCRIPTIONS_URL}/sub-email-1`);
        expect(JSON.parse(fetchMock.mock.calls[1][1].body)).toEqual({
            subscription: {
                enabled: false,
                notification_types: -2,
            },
        });
        expect(result).toMatchObject({ success: true, subscriptionId: "sub-email-1" });
    });
    test("non patcha se la subscription email è già disabilitata", async () => {
        fetchMock.mockResolvedValueOnce(mockFetchResponse(200, {
            subscriptions: [
                { id: "sub-email-1", type: "Email", token: "test@example.com", enabled: false },
            ],
        }));
        const request = {
            auth: { uid: "user-1" },
            data: { email: "test@example.com" },
        };
        const result = await (0, handler_1.removeOneSignalEmailHandler)(request, API_KEY);
        expect(result).toMatchObject({
            alreadyRemoved: true,
            reason: "already_disabled",
            subscriptionId: "sub-email-1",
        });
        expect(fetchMock).toHaveBeenCalledTimes(1);
    });
});
//# sourceMappingURL=handler.test.js.map