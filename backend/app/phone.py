"""Phone number validation + normalisation to E.164. Ethiopian formats are accepted in all common local spellings."""
import re


class PhoneError(ValueError):
    pass


def normalize_phone(raw: str) -> str:
    s = re.sub(r"[\s\-().]", "", raw or "")
    if not s:
        raise PhoneError("Phone number is required")
    if not re.fullmatch(r"\+?\d+", s):
        raise PhoneError("Phone number may only contain digits, spaces, dashes and a leading +")
    if s.startswith("00"):
        s = "+" + s[2:]
    if s.startswith("+"):
        digits = s[1:]
        if digits.startswith("251"):
            national = digits[3:]
            if not re.fullmatch(r"[79]\d{8}", national):
                raise PhoneError("Enter a valid Ethiopian mobile number, e.g. 0912 345 678")
            return "+251" + national
        if not 8 <= len(digits) <= 15 or digits.startswith("0"):
            raise PhoneError("Enter a valid phone number including the country code")
        return "+" + digits
    if s.startswith("251") and len(s) == 12:
        return normalize_phone("+" + s)
    if re.fullmatch(r"0[79]\d{8}", s):                 # 09XXXXXXXX / 07XXXXXXXX
        return "+251" + s[1:]
    if re.fullmatch(r"[79]\d{8}", s):                  # 9XXXXXXXX
        return "+251" + s
    raise PhoneError("Enter a valid Ethiopian mobile number, e.g. 0912 345 678, or use the +country format")


def looks_like_phone(raw: str) -> bool:
    s = re.sub(r"[\s\-().+]", "", raw or "")
    return bool(s) and s.isdigit()


def name_key(name: str) -> str:
    return " ".join((name or "").split()).casefold()


USERNAME_RE = re.compile(r"[A-Za-z0-9_.]{3,30}")


def normalize_username(raw: str) -> str:
    """Usernames are case-insensitive: stored lower-case. Letters, digits, underscore and dot; 3-30 characters."""
    v = (raw or "").strip()
    if not USERNAME_RE.fullmatch(v):
        raise ValueError("Username must be 3-30 characters: letters, numbers, underscore or dot")
    if v.isdigit():
        raise ValueError("Username cannot be only digits (it could be mistaken for a phone number)")
    return v.lower()
