import type { ComponentChildren } from 'preact';
import { useEffect, useRef, useState } from 'preact/hooks';
import { CODE_LENGTH, RESEND_SECONDS, type AuthService, type SignedIn } from '../auth/auth';
import type { Captcha } from '../auth/turnstile';
import type { Failure } from '../core/failure';
import { maskEmail, normalizeCode, normalizeEmail } from '../core/text';
import { useI18n, type MessageKey } from '../i18n';
import { Icon } from '../ui/icons';
import { withSlot } from '../ui/rich';

interface Props {
  readonly captcha: Captcha | null;
  readonly auth: AuthService;
  readonly online: boolean;
  readonly onSignedIn: (user: SignedIn) => void;
}

type Step = 'email' | 'code';
type Busy = 'none' | 'sending' | 'verifying';
type Problem = 'email_invalid' | 'code_invalid' | 'code_wrong' | 'code_expired' | 'rate_limited' | 'offline' | 'captcha' | 'other';

function problemOf(failure: Failure): Problem {
  switch (failure.kind) {
    case 'code_wrong':
      return 'code_wrong';
    case 'code_expired':
      return 'code_expired';
    case 'rate_limited':
      return 'rate_limited';
    case 'offline':
      return 'offline';
    default:
      return 'other';
  }
}

function clock(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = String(seconds % 60).padStart(2, '0');
  return `${m}:${s}`;
}

export function SignInPage({ auth, captcha, online, onSignedIn }: Props) {
  const { t, lang } = useI18n();
  const captchaBox = useRef<HTMLDivElement>(null);
  const [step, setStep] = useState<Step>('email');
  const [emailText, setEmailText] = useState('');
  const [email, setEmail] = useState(''); // the normalized address a code was sent to
  const [codeText, setCodeText] = useState('');
  const [busy, setBusy] = useState<Busy>('none');
  const [problem, setProblem] = useState<Problem | null>(null);
  const [wait, setWait] = useState(0);
  const heading = useRef<HTMLHeadingElement>(null);
  const emailInput = useRef<HTMLInputElement>(null);
  const codeInput = useRef<HTMLInputElement>(null);
  const first = useRef(true);
  const inFlight = useRef(false);

  useEffect(() => {
    if (first.current) {
      first.current = false;
      return;
    }
    heading.current?.focus();
  }, [step]);

  const counting = wait > 0;
  useEffect(() => {
    if (!counting) return;
    const id = window.setInterval(() => {
      setWait((w) => Math.max(0, w - 1));
    }, 1000);
    return () => {
      window.clearInterval(id);
    };
  }, [counting]);

  const request = async (address: string, from: Step) => {
    if (inFlight.current) return;
    inFlight.current = true;
    setBusy('sending');
    setProblem(null);
    let token: string | undefined;
    if (captcha && captchaBox.current) {
      try {
        token = await captcha.token(captchaBox.current, lang);
      } catch {
        inFlight.current = false;
        setBusy('none');
        setProblem('captcha');
        return;
      }
    }
    const result = token === undefined ? await auth.sendCode(address) : await auth.sendCode(address, token);
    inFlight.current = false;
    setBusy('none');
    if (result.ok) {
      setEmail(address);
      setCodeText('');
      setWait(RESEND_SECONDS);
      setStep('code');
      return;
    }
    setProblem(problemOf(result.failure));
    if (from === 'code') setWait(RESEND_SECONDS);
  };

  const submitEmail = (event: Event) => {
    event.preventDefault();
    if (!online || busy !== 'none') return;
    const address = normalizeEmail(emailText);
    if (!address) {
      setProblem('email_invalid');
      emailInput.current?.focus();
      return;
    }
    void request(address, 'email');
  };

  const submitCode = async (event: Event) => {
    event.preventDefault();
    if (!online || busy !== 'none' || inFlight.current) return;
    const digits = normalizeCode(codeText, CODE_LENGTH);
    if (!digits) {
      setProblem('code_invalid');
      codeInput.current?.focus();
      return;
    }
    inFlight.current = true;
    setBusy('verifying');
    setProblem(null);
    const result = await auth.verifyCode(email, digits);
    inFlight.current = false;
    setBusy('none');
    if (result.ok) {
      onSignedIn(result.value);
      return;
    }
    setProblem(problemOf(result.failure));
  };

  const otherEmail = () => {
    setProblem(null);
    setCodeText('');
    setWait(0);
    setStep('email');
  };

  const offlineHint = online ? null : <span class="cap">{t('signIn.offlineHint')}</span>;
  const failureLine = (key: MessageKey, id: string): ComponentChildren => (
    <span id={id} class="errt" role="alert">
      <Icon name="alert" />
      {t(key)}
    </span>
  );
  const generic: ComponentChildren =
    problem === 'rate_limited' ? (
      failureLine('signIn.rateLimited', 'sign-in-problem')
    ) : problem === 'offline' ? (
      <div class="banner off" role="alert">
        <Icon name="offline" />
        {t('state.offline')}
      </div>
    ) : problem === 'captcha' ? (
      <div class="banner err" role="alert">
        <Icon name="alert" />
        {t('signIn.captchaFailed')}
      </div>
    ) : problem === 'other' ? (
      <div class="banner err" role="alert">
        <Icon name="alert" />
        {t('state.errorBody')}
      </div>
    ) : null;

  if (step === 'email') {
    const bad = problem === 'email_invalid';
    return (
      <div class="page-center">
        <form class="card roomy" noValidate onSubmit={submitEmail}>
          <div class="stack-sm">
            <h1 class="h1" ref={heading} tabIndex={-1}>{t('signIn.title')}</h1>
            <p class="sub">{t('signIn.subtitle')}</p>
          </div>
          <div class="field">
            <label for="sign-in-email">{t('signIn.email')}</label>
            <input
              id="sign-in-email"
              ref={emailInput}
              class={`in${bad ? ' bad' : ''}`}
              type="email"
              name="email"
              autoComplete="email"
              inputMode="email"
              maxLength={254}
              value={emailText}
              disabled={busy === 'sending'}
              aria-invalid={bad ? 'true' : undefined}
              aria-describedby={bad ? 'sign-in-email-error sign-in-email-hint' : 'sign-in-email-hint'}
              onInput={(event) => {
                setEmailText(event.currentTarget.value);
                if (problem === 'email_invalid') setProblem(null);
              }}
            />
            <span id="sign-in-email-hint" class="hint">{t('signIn.emailHint', { length: CODE_LENGTH })}</span>
            {bad ? failureLine('signIn.emailInvalid', 'sign-in-email-error') : null}
          </div>
          {generic}
          <button type="submit" class="btn pri" disabled={!online || busy === 'sending'} aria-busy={busy === 'sending'}>
            {busy === 'sending' ? (
              <>
                <span class="skel spin" aria-hidden="true" />
                {t('signIn.sending')}
              </>
            ) : (
              t('signIn.send')
            )}
          </button>
          {offlineHint}
          <div class="captcha" ref={captchaBox} />
        </form>
      </div>
    );
  }

  const expired = problem === 'code_expired';
  const codeBad = problem === 'code_wrong' || problem === 'code_invalid';
  const resend =
    wait > 0 ? (
      <span class="cap">{withSlot(t('signIn.resendIn'), 'time', <span class="num">{clock(wait)}</span>)}</span>
    ) : (
      <button type="button" class="btn sm" disabled={!online || busy !== 'none'} onClick={() => { void request(email, 'code'); }}>
        {t('signIn.resend')}
      </button>
    );

  return (
    <div class="page-center">
      <div class="card roomy">
        <div class="stack-sm">
          <h1 class="h1" ref={heading} tabIndex={-1}>{t('signIn.checkTitle')}</h1>
          <p class="sub">
            {withSlot(t('signIn.checkBody', { length: CODE_LENGTH }), 'email', <b class="num">{maskEmail(email)}</b>)}
          </p>
        </div>
        {expired ? (
          <div class="stack">
            <div class="banner err" role="alert">
              <Icon name="clock" />
              {t('signIn.codeExpired')}
            </div>
            <p class="sub">{t('signIn.codeExpiredBody')}</p>
            <button type="button" class="btn pri" disabled={!online || busy !== 'none'} aria-busy={busy === 'sending'} onClick={() => { void request(email, 'code'); }}>
              {busy === 'sending' ? t('signIn.sending') : t('signIn.sendNew')}
            </button>
            {offlineHint}
          </div>
        ) : (
          <form class="stack" noValidate onSubmit={(event) => { void submitCode(event); }}>
            <div class="field">
              <label for="sign-in-code">{t('signIn.code')}</label>
              <input
                id="sign-in-code"
                ref={codeInput}
                class={`in otp-in${codeBad ? ' bad' : ''}`}
                type="text"
                name="code"
                autoComplete="one-time-code"
                inputMode="numeric"
                maxLength={10}
                value={codeText}
                disabled={busy === 'verifying'}
                aria-invalid={codeBad ? 'true' : undefined}
                aria-describedby={codeBad ? 'sign-in-code-error sign-in-code-hint' : 'sign-in-code-hint'}
                onInput={(event) => {
                  setCodeText(event.currentTarget.value);
                  if (problem === 'code_invalid' || problem === 'code_wrong') setProblem(null);
                }}
              />
              <span id="sign-in-code-hint" class="hint">{t('signIn.codeHint')}</span>
              {problem === 'code_wrong' ? failureLine('signIn.codeWrong', 'sign-in-code-error') : null}
              {problem === 'code_invalid' ? (
                <span id="sign-in-code-error" class="errt" role="alert">
                  <Icon name="alert" />
                  {t('signIn.codeInvalid', { length: CODE_LENGTH })}
                </span>
              ) : null}
            </div>
            {generic}
            <button type="submit" class="btn pri" disabled={!online || busy === 'verifying'} aria-busy={busy === 'verifying'}>
              {busy === 'verifying' ? t('signIn.verifying') : t('signIn.verify')}
            </button>
            {offlineHint}
          </form>
        )}
        <div class="row-between">
          <button type="button" class="btn ghost sm" onClick={otherEmail}>{t('signIn.otherEmail')}</button>
          {expired ? null : resend}
        </div>
        <div class="captcha" ref={captchaBox} />
      </div>
    </div>
  );
}
