import Foundation

enum Scripts {
    static let activityHandler = "kioskActivity"
    static let loginHandler = "kioskLogin"

    /// Нажатия на экранную клавиатуру не доходят до нативных жестов, поэтому активность
    /// дополнительно ловим событиями внутри страницы (во всех фреймах).
    static let activityTracker = """
    (function () {
      var last = 0;
      function ping() {
        var now = Date.now();
        if (now - last < 1000) { return; }
        last = now;
        try { window.webkit.messageHandlers.\(activityHandler).postMessage(1); } catch (e) {}
      }
      ['touchstart', 'pointerdown', 'keydown', 'input', 'scroll', 'wheel'].forEach(function (type) {
        document.addEventListener(type, ping, { capture: true, passive: true });
      });
    })();
    """

    /// Убирает системное меню долгого нажатия на ссылки и картинки («Поделиться», «Открыть в…»).
    static let disableCallout = """
    (function () {
      var style = document.createElement('style');
      style.textContent = '* { -webkit-touch-callout: none !important; }';
      document.documentElement.appendChild(style);
    })();
    """

    /// Заполняет форму Яндекс ID. Форма — SPA (логин и пароль на разных шагах без перезагрузки),
    /// поэтому скрипт опрашивает DOM и проходит шаги по мере появления полей.
    /// Пароль отправляется не больше одного раза за загрузку страницы, чтобы не заблокировать учётку.
    static func autoLogin(_ credentials: Credentials, allowedHosts: Set<String>) -> String {
        let payload: [String: Any] = [
            "login": credentials.login,
            "password": credentials.password,
            "hosts": Array(allowedHosts),
        ]
        let json = (try? JSONSerialization.data(withJSONObject: payload))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        return """
        (function (creds) {
          if (!creds.hosts || creds.hosts.indexOf(location.hostname) < 0) { return; }
          if (window.__kioskAutoLogin) { return; }
          window.__kioskAutoLogin = true;

          function isVisible(el) { return !!el && el.offsetParent !== null && !el.disabled; }

          function setValue(input, value) {
            var setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
            input.focus();
            setter.call(input, value);
            input.dispatchEvent(new Event('input', { bubbles: true }));
            input.dispatchEvent(new Event('change', { bubbles: true }));
          }

          function submit(input) {
            var button = document.querySelector(
              '[id="passp:sign-in"], button[data-t="button:action:passp:sign-in"], button[type="submit"]'
            );
            if (button && !button.disabled) { button.click(); return; }
            if (input.form) {
              if (input.form.requestSubmit) { input.form.requestSubmit(); } else { input.form.submit(); }
            }
          }

          function findVisible(selector, predicate) {
            return Array.prototype.find.call(document.querySelectorAll(selector), function (el) {
              return isVisible(el) && predicate((el.textContent || '').toLowerCase());
            });
          }

          var login = creds.login.toLowerCase();
          var done = {};
          var ticks = 0;
          var timer = setInterval(function () {
            if (++ticks > 60) { clearInterval(timer); return; }

            var passwordInput = document.querySelector('input[name="passwd"], input[type="password"]');
            if (isVisible(passwordInput)) {
              if (!done.password) {
                done.password = true;
                setValue(passwordInput, creds.password);
                try { window.webkit.messageHandlers.\(loginHandler).postMessage('password'); } catch (e) {}
                setTimeout(function () { submit(passwordInput); }, 300);
              }
              return;
            }

            var loginInput = document.querySelector('input[name="login"]');
            if (isVisible(loginInput)) {
              if (!done.login) {
                done.login = true;
                setValue(loginInput, creds.login);
                setTimeout(function () { submit(loginInput); }, 300);
              }
              return;
            }

            var phoneInput = document.querySelector('input[type="tel"], input[name="phone"]');
            if (isVisible(phoneInput)) {
              if (!done.switchToLogin) {
                var tab = findVisible('button, [role="tab"], [role="button"]', function (text) {
                  return /почт|логин|e-?mail|login/.test(text);
                });
                if (tab) { done.switchToLogin = true; tab.click(); }
              }
              return;
            }

            if (!done.account && !done.login) {
              var account = findVisible('a, button, [role="button"]', function (text) {
                return text.indexOf(login) >= 0;
              });
              if (account) { done.account = true; account.click(); }
            }
          }, 500);
        })(\(json));
        """
    }
}
