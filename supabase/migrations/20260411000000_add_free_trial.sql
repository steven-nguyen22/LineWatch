-- Add free trial tracking columns to profiles
ALTER TABLE profiles ADD COLUMN trial_started_at TIMESTAMPTZ;
ALTER TABLE profiles ADD COLUMN trial_ends_at TIMESTAMPTZ;
ALTER TABLE profiles ADD COLUMN trial_acknowledged BOOLEAN NOT NULL DEFAULT false;

-- Update the new-user trigger to start a 7-day Hall of Fame trial automatically.
-- Existing rows are untouched (trial_ends_at stays NULL → no trial granted).
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (
        id, full_name, email, avatar_url,
        trial_started_at, trial_ends_at
    )
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', ''),
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'avatar_url', ''),
        now(),
        now() + interval '7 days'
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
