// Inserted as a SettingsController method. OAuth grants stay in the Host credential service.
async mikuCodex(action, owner) {
    const key = "llm-pi-ai/openai-codex";
    const auth = this.ctx.get("authorization");
    const credentials = this.ctx.get("credentials");
    if (!auth || !credentials || !auth.describe(key)?.methods.some(m => m.id === "oauth"))
        throw Error("Codex OAuth provider unavailable");
    const status = async () => {
        const attempt = this.mikuCodexAttempt;
        if (attempt && attempt.owner === owner) return {phase:attempt.phase,code:attempt.code};
        return {phase:(await credentials.describeRecord(key)).kind === "grant" ? "connected" : "idle",code:""};
    };
    if (action === "status") return status();
    const previous = this.mikuCodexAttempt;
    if (action === "cancel") {
        if (previous?.owner === owner && previous.phase === "waiting") previous.controller.abort();
        return status();
    }
    const settings = this.provider();
    const route = "openai-codex";
    const scope = () => settings.describe({redactSecrets:true}).find(x => x.ns === "llm-pi-ai");
    const checkProfile = () => {
        const view = scope();
        if (!view) throw Error("Provider settings unavailable");
        const profile = view.value.providers?.[route];
        if (profile && (profile.baseURL || profile.api || profile.apiKeyEnv || Object.keys(profile.modelOverrides || {}).length || Object.keys(profile.headers || {}).length))
            throw Error("Use the official openai-codex route without custom credentials or endpoints");
        return {view,profile};
    };
    const enable = async () => {
        const {view,profile} = checkProfile();
        if (!profile) await settings.mutate(view.ns,[{op:"set",path:["providers",route],value:{displayName:"ChatGPT (Codex)"}}],view.revision);
    };
    if (action !== "start") throw Error("Unknown sign-in action");
    checkProfile();
    if (previous?.phase === "waiting") return status();
    if ((await credentials.describeRecord(key)).kind === "grant") {
        await enable();
        this.mikuCodexAttempt = undefined;
        return status();
    }
    if (this.mikuCodexAttempt?.phase === "waiting") return status();
    const attempt = {owner,phase:"waiting",code:"",controller:new AbortController()};
    this.mikuCodexAttempt = attempt;
    const timeout = setTimeout(() => attempt.controller.abort(), 15*60*1000);
    auth.begin({key,method:"oauth",signal:attempt.controller.signal,interaction:{
        prompt:async p => {
            if (p.kind === "select" && p.options.some(x => x.id === "device_code")) return "device_code";
            throw Error("Unsupported Codex prompt");
        },
        notify:n => {
            if (n.url === "https://auth.openai.com/codex/device" && typeof n.code === "string") attempt.code=n.code;
        }
    }}).then(async outcome => {
        if (outcome.status === "authorized") { await enable(); attempt.phase="connected"; }
        else attempt.phase="cancelled";
    }).catch(() => {attempt.phase="failed";}).finally(() => {attempt.code="";clearTimeout(timeout);});
    return status();
}
