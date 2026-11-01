-- The app was renamed to Azm (com.mohager.azm) before its first release.
-- Point the update dialog's store link at the new Play listing. 0001 is left
-- as it was (already applied migrations are never edited).
-- iOS keeps its placeholder until the App Store app id is known.
update public.app_versions
set store_url = 'https://play.google.com/store/apps/details?id=com.mohager.azm',
    updated_at = now()
where platform = 'android'
  and store_url like '%com.mohager.gymtracker%';
