import pytest

from friends_api.features.books.isbn import guess_genre, image_type, normalize_isbn
from friends_api.features.books.models import BookGenre


@pytest.mark.parametrize(
    ("value", "expected"),
    [
        ("9780441172719", "9780441172719"),
        ("978-0-441-17271-9", "9780441172719"),
        ("0441172717", "9780441172719"),
        ("0 441 17271 7", "9780441172719"),
        ("080442957X", "9780804429573"),
        ("080442957x", "9780804429573"),
        ("9791032305690", "9791032305690"),
        ("9780441172718", None),  # check digit
        ("0441172718", None),
        ("9770441172719", None),  # not a book prefix
        ("97804411727", None),
        ("abcdefghij", None),
        ("", None),
    ],
)
def test_normalize_isbn(value: str, expected: str | None) -> None:
    assert normalize_isbn(value) == expected


@pytest.mark.parametrize(
    ("subjects", "expected"),
    [
        (["Fiction / Science Fiction / General"], BookGenre.SCI_FI),
        (["Juvenile Fiction"], BookGenre.CHILDREN),
        (["Young Adult Fiction / Fantasy"], BookGenre.YOUNG_ADULT),
        (["Comics & Graphic Novels"], BookGenre.COMICS),
        (["Biography & Autobiography"], BookGenre.BIOGRAPHY),
        (["History"], BookGenre.HISTORY),
        (["Fiction"], BookGenre.FICTION),
        (["Cooking"], None),
        ([], None),
    ],
)
def test_guess_genre(subjects: list[str], expected: BookGenre | None) -> None:
    assert guess_genre(subjects) == expected


def test_image_type() -> None:
    assert image_type(b"\xff\xd8\xff\xe0rest") == "image/jpeg"
    assert image_type(b"\x89PNG\r\n\x1a\nrest") == "image/png"
    assert image_type(b"RIFF\x00\x00\x00\x00WEBPVP8 ") == "image/webp"
    assert image_type(b"GIF89a") is None
    assert image_type(b"") is None
