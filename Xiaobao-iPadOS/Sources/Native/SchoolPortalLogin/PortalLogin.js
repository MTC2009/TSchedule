// Private WebKit world, exact first-party login screen only. No fetch, cookies,
// guessed endpoints, password reads, challenge handling or arbitrary selectors.
async (operation, loginName, password) => {
    const origin = "https://tsinglanstudent.schoolis.cn";
    const official = () => window === window.top && location.origin === origin && !location.username && !location.password &&
        /^\/(?:account\/login\/?)?$/i.test(location.pathname) && !location.search && !location.hash &&
        new URL(document.baseURI).origin === origin;
    const reset = () => {
        const written = globalThis.tScheduleFilledLogin;
        delete globalThis.tScheduleFilledLogin;
        if (written && official()) for (const el of written) if (el.isConnected) {
            el.value = "";
            el.dispatchEvent(new Event("input",{bubbles:true}));
            el.dispatchEvent(new Event("change",{bubbles:true}));
        }
    };
    if (operation === "clear") { reset(); return "cleared"; }
    if (!official()) return "blocked";
    const shown = el => el.isConnected && el.getClientRects().length > 0 &&
        getComputedStyle(el).visibility === "visible";
    const pending = document.readyState === "loading" || !document.body;
    if (pending) return "waiting";
    const notice = () => {
        const text = document.body.innerText;
        if (document.querySelector('iframe,frame,input[autocomplete="one-time-code"],[data-sitekey]') ||
            /验证码|驗證碼|人机验证|安全验证|短信验证|滑块|captcha|one.time.code|verification code/i.test(text)) return "blocked";
        if (/密码错误|密码有误|密码不正确|用户名不存在|登录失败|账号已锁定|incorrect password|password is incorrect|login failed/i.test(text)) return "rejected";
        const dialogs = [...document.querySelectorAll('[role="dialog"],[aria-modal="true"]')].filter(shown);
        if (dialogs.some(d => operation !== "observe" ||
            !(d.getAttribute("aria-busy") === "true" || /^(?:正在(?:登录|加载)|loading)[.…。\s]*$/i.test(d.innerText.trim())))) return "blocked";
        return null;
    };
    // After the click, never look for writable controls again. A disabled or replaced
    // submit button is normal while the school's own handler waits for its response.
    if (operation === "observe") return notice() ?? "waiting";
    function controls() {
        if (!official()) return "blocked";
        if (notice()) return "blocked";
        const fields = [...document.querySelectorAll('input:not([type="hidden"]),textarea,select')].filter(shown);
        if (!fields.length) return "waiting";
        const names = fields.filter(e => e.type === "text" && e.placeholder === "请输入用户名");
        const secrets = fields.filter(e => e.type === "password" && e.placeholder === "请输入密码");
        const buttons = [...document.querySelectorAll('button,[role="button"],input[type="submit"]')].filter(shown);
        if (fields.length !== 2 || names.length !== 1 || secrets.length !== 1 || buttons.length !== 1) return "blocked";
        const [name, secret, submit] = [names[0], secrets[0], buttons[0]];
        // The published student entry has two unowned inputs and one official
        // button. An added form/action (especially a GET), role or field is a new contract.
        if (submit.tagName !== "BUTTON" || submit.innerText.trim() !== "登录" || submit.type !== "submit" ||
            name.form || secret.form || submit.form || submit.hasAttribute("formaction") ||
            name.disabled || secret.disabled || name.readOnly || secret.readOnly ||
            submit.disabled || submit.getAttribute("aria-disabled") === "true") return "blocked";
        return [name, secret, submit];
    }
    const match = controls();
    if (typeof match === "string") return match;
    if (operation === "probe") return "ready";
    if (operation !== "submit" || !loginName || !password) return "blocked";
    const [name, secret, submit] = match;
    if (globalThis.tScheduleFilledLogin) return "blocked";
    globalThis.tScheduleFilledLogin = [name, secret];
    const same = () => {
        const check = controls();
        return Array.isArray(check) && check.every((e,i) => e === match[i]);
    };
    try {
        for (const [el, value] of [[name, loginName], [secret, password]]) {
            if (!same()) { reset(); return "blocked"; }
            el.value = value;
            el.dispatchEvent(new Event("input", {bubbles:true}));
            el.dispatchEvent(new Event("change", {bubbles:true}));
        }
        await Promise.resolve();
        if (!same() || submit.disabled || submit.getAttribute("aria-disabled") === "true") { reset(); return "blocked"; }
        submit.click(); // Let the school perform its own ordinary authentication.
        return "submitted";
    } catch { reset(); return "blocked"; }
}
