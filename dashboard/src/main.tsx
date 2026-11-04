import { render } from 'preact';
import { App } from './app/App';
import { AuthService } from './auth/auth';
import { TurnstileCaptcha } from './auth/turnstile';
import { ConfigError, parseConfig } from './core/config';
import { makeSupabase } from './core/supabase';
import { GymsRepository } from './gyms/gyms';
import { ConfigErrorPage } from './ui/states';
import './styles/app.css';

const root = document.getElementById('app');
if (root) {
  try {
    const config = parseConfig(import.meta.env);
    const supabase = makeSupabase(config);
    const services = {
      auth: new AuthService(supabase),
      gyms: new GymsRepository(supabase),
      captcha: config.turnstileSiteKey ? new TurnstileCaptcha(config.turnstileSiteKey) : null,
    };
    render(<App services={services} />, root);
  } catch (error: unknown) {
    if (!(error instanceof ConfigError)) throw error;
    render(<ConfigErrorPage />, root);
  }
}
