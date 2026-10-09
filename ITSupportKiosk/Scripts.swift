import Foundation

enum Scripts {
    static let activityHandler = "kioskActivity"
    static let loginHandler = "kioskLogin"
    static let debugHandler = "kioskDebug"

    static let errorReporter = """
    (function () {
      function send(text) {
        try { window.webkit.messageHandlers.\(debugHandler).postMessage(location.host + ': ' + text); } catch (e) {}
      }
      window.addEventListener('error', function (event) {
        send('JS error: ' + event.message + ' @ ' + event.filename + ':' + event.lineno);
      });
      window.addEventListener('unhandledrejection', function (event) {
        send('Unhandled rejection: ' + (event.reason && (event.reason.stack || event.reason)));
      });
    })();
    """

    static let pageSummary = """
    (function () {
      var body = document.body;
      var controls = Array.prototype.map.call(
        document.querySelectorAll('input:not([type="hidden"]), button, [role="button"], span.submit'),
        function (el) { return el.tagName.toLowerCase() + '#' + el.id + '[' + (el.name || '') + ',' + (el.type || '') + ']'; }
      ).join(' ');
      return document.readyState + ' | title="' + document.title + '" | text=' +
        (body ? body.innerText.length : -1) + ' | ' + (body ? body.innerText.slice(0, 200).replace(/\\s+/g, ' ') : '') +
        ' | controls: ' + controls.slice(0, 600);
    })();
    """

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

    /// Проходит цепочку входа: Yandex Cloud («Войти с помощью Yandex») → Яндекс ID (почта) →
    /// корпоративный ADFS (логин и пароль) → код 2FA, если задан секрет TOTP.
    /// Формы меняются без перезагрузки страницы, поэтому скрипт опрашивает DOM.
    /// Пароль и код отправляются не больше одного раза за загрузку страницы и не отправляются,
    /// если форма показывает ошибку, чтобы не заблокировать учётку.
    static func autoLogin(_ credentials: Credentials, totpCode: String?, allowedHosts: Set<String>) -> String {
        let payload: [String: Any] = [
            "login": credentials.login,
            "password": credentials.password,
            "totp": totpCode ?? "",
            "hosts": Array(allowedHosts),
        ]
        let json = (try? JSONSerialization.data(withJSONObject: payload))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        return """
        (function (creds) {
          var host = location.hostname;
          if (!creds.hosts || creds.hosts.indexOf(host) < 0) { return; }
          if (window.__kioskAutoLogin) { return; }
          window.__kioskAutoLogin = true;

          var USER_FIELDS = 'input[name="login"], #userNameInput, input[name="UserName"]' +
            (host === 'passport.yandex.ru' ? ', input[type="email"], input[type="text"]' : '');
          var PASSWORD_FIELDS = 'input[name="passwd"], #passwordInput, input[name="Password"]';
          var TOTP_FIELDS = '#totp, input[name="totp"]';
          var SUBMIT_BUTTONS = '#continueButton, #submitButton, #nextButton, [id="passp:sign-in"], ' +
            'button[data-t="button:action:passp:sign-in"], button[type="submit"], input[type="submit"]';

          function isVisible(el) { return !!el && el.offsetParent !== null && !el.disabled; }

          function first(selector) {
            return Array.prototype.find.call(document.querySelectorAll(selector), isVisible);
          }

          function findVisible(selector, predicate) {
            return Array.prototype.find.call(document.querySelectorAll(selector), function (el) {
              return isVisible(el) && predicate((el.textContent || '').toLowerCase().replace(/\\s+/g, ' '));
            });
          }

          function setValue(input, value) {
            var setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
            input.focus();
            setter.call(input, value);
            input.dispatchEvent(new Event('input', { bubbles: true }));
            input.dispatchEvent(new Event('change', { bubbles: true }));
          }

          function submit(input) {
            var button = first(SUBMIT_BUTTONS) || findVisible('button, [role="button"]', function (text) {
              return /^(далее|войти|вход|next|sign in|log in)$/.test(text.trim());
            });
            if (button) { button.click(); return; }
            if (input.form) {
              if (input.form.requestSubmit) { input.form.requestSubmit(); } else { input.form.submit(); }
            }
          }

          function hasError() {
            var error = document.querySelector('#errorText');
            return !!error && (error.innerText || '').trim().length > 0;
          }

          var login = creds.login.toLowerCase();
          var done = {};
          var ticks = 0;
          var timer = setInterval(function () {
            if (++ticks > 60 || hasError()) { clearInterval(timer); return; }

            var totpInput = first(TOTP_FIELDS);
            if (totpInput) {
              if (!done.totp && creds.totp) {
                done.totp = true;
                setValue(totpInput, creds.totp);
                try { window.webkit.messageHandlers.\(loginHandler).postMessage('totp'); } catch (e) {}
                setTimeout(function () { submit(totpInput); }, 300);
              }
              return;
            }

            var passwordInput = first(PASSWORD_FIELDS);
            if (passwordInput) {
              if (!done.password) {
                done.password = true;
                var userInput = first(USER_FIELDS);
                if (userInput && !userInput.value) { setValue(userInput, creds.login); }
                setValue(passwordInput, creds.password);
                var keepSignedIn = document.querySelector('#kmsiInput');
                if (keepSignedIn && !keepSignedIn.checked) { keepSignedIn.click(); }
                try { window.webkit.messageHandlers.\(loginHandler).postMessage('password'); } catch (e) {}
                setTimeout(function () { submit(passwordInput); }, 300);
              }
              return;
            }

            var phoneInput = host === 'passport.yandex.ru' && first('input[type="tel"], input[name="phone"]');
            if (phoneInput) {
              if (!done.switchToLogin) {
                var tab = findVisible('label, button, [role="tab"], [role="radio"], [role="button"]', function (text) {
                  return /почт|логин|e-?mail|login/.test(text);
                });
                if (tab) { done.switchToLogin = true; tab.click(); }
              }
              return;
            }

            var loginInput = first(USER_FIELDS);
            if (loginInput) {
              if (!done.login) {
                done.login = true;
                setValue(loginInput, creds.login);
                setTimeout(function () { submit(loginInput); }, 300);
              }
              return;
            }

            if (host.indexOf('auth.cloud.yandex.') === 0) {
              if (!done.cloud) {
                var yandexButton = findVisible('button, a, [role="button"]', function (text) {
                  return text.indexOf('войти с помощью yandex') >= 0 || text.indexOf('log in with yandex') >= 0;
                });
                if (yandexButton) { done.cloud = true; yandexButton.click(); }
              }
              return;
            }

            if (host !== 'passport.yandex.ru') { return; }

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
