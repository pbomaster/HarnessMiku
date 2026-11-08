from pathlib import Path

def only(text, match, replacement):
    if text.count(match) != 1:
        raise ValueError("Unsupported Codex integration point: " + match[:60])
    return text.replace(match, replacement)

def controller(text):
    anchor = '__esDecorate(this, null, _openSettingsDocument_decorators, {'
    pos = text.index(anchor)
    end = text.index('_instanceExtraInitializers);', pos) + len('_instanceExtraInitializers);')
    decorator = text[pos:end]
    text = only(text, decorator, decorator + '\n' + decorator.replace('"openSettingsDocument"', '"mikuCodex"').replace('obj.openSettingsDocument','obj.mikuCodex'))
    method = Path(__file__).with_name("codex-host.js").read_text(encoding="utf8")
    return only(text, 'async openSettingsDocument(signal) {', method+'\nasync openSettingsDocument(signal) {')

def metadata(text):
    anchor = "'settings/openSettingsDocument': {"
    method = """'settings/mikuCodex': {
        service: 'settingsController',
        description: 'Start or inspect the desktop Codex device authorization.',
        invocation: {kind:'direct'},
        parameters: ['action','owner'].map(name => {
            const codec={mode:'strict',typeSymbol:'miku-codex:'+name,
                create:() => name==='owner' ? z.string().uuid() : z.enum(['start','cancel','status']),
                jsonSchema:{type:'string'}};
            return {name,source:'json',codec,strictCodec:codec};
        }),
        result: {mode:'strict',typeSymbol:'miku-codex:state',create:()=>z.object({phase:z.string(),code:z.string()}),jsonSchema:{type:'object'}},
    },
    """
    return only(text,anchor,method+anchor)
