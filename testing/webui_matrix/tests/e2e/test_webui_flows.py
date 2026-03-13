from __future__ import annotations

import unittest

from testing.webui_matrix.tests.support import LiveVariantCase, discover_live_variants, login_session


class WebUiE2ETestMixin:
    def test_login_page_reflects_backend_mode(self) -> None:
        assert self.VARIANT is not None

        response = self.http_client().get(self.VARIANT.frontend_login_url)
        self.assertEqual(200, response.status, response.text)
        self.assertIn(self.VARIANT.expected_frontend_label, response.text)
        self.assertIn(self.VARIANT.expected_frontend_summary, response.text)

    def test_root_redirects_to_login_and_blocks_api_without_session(self) -> None:
        assert self.VARIANT is not None

        root = self.http_client().get(
            self.VARIANT.frontend_base_url + "/",
            follow_redirects=False,
        )
        self.assertEqual(302, root.status, root.text)
        self.assertIn("/login", root.headers.get("Location", ""))

        unauthenticated_api = self.http_client().get(
            self.VARIANT.frontend_flights_url,
            follow_redirects=False,
        )
        self.assertEqual(401, unauthenticated_api.status, unauthenticated_api.text)
        self.assertIn("frontend_auth_required", unauthenticated_api.text)

    def test_logged_in_traveler_can_book_and_cannot_read_another_user(self) -> None:
        assert self.VARIANT is not None

        client = self.http_client()
        login_response = login_session(client, self.VARIANT)
        self.assertIn(self.VARIANT.expected_frontend_label, login_response.text)

        traveler_response = client.get(self.VARIANT.frontend_traveler_url)
        self.assertEqual(200, traveler_response.status, traveler_response.text)
        traveler = traveler_response.json()
        traveler_id = int(traveler["traveler_id"])
        self.assertGreater(traveler_id, 0)

        flights_response = client.get(self.VARIANT.frontend_flights_url)
        self.assertEqual(200, flights_response.status, flights_response.text)
        flights = flights_response.json()
        self.assertIsInstance(flights, list)
        self.assertGreater(len(flights), 0)
        first_flight_id = int(flights[0]["flight_id"])

        book_response = client.post_json(
            self.VARIANT.frontend_book_url,
            {"flight_id": first_flight_id},
        )
        self.assertEqual(200, book_response.status, book_response.text)
        booking = book_response.json()
        self.assertEqual(traveler_id, int(booking["user_id"]))
        self.assertGreater(int(booking["booking_id"]), 0)

        bookings_response = client.get(self.VARIANT.frontend_bookings_url)
        self.assertEqual(200, bookings_response.status, bookings_response.text)
        bookings = bookings_response.json()
        self.assertTrue(any(int(item["booking_id"]) == int(booking["booking_id"]) for item in bookings))

        forbidden = client.get(
            self.VARIANT.frontend_base_url + f"/api/bookings/{traveler_id + 1}",
            follow_redirects=False,
        )
        self.assertEqual(403, forbidden.status, forbidden.text)
        self.assertIn("Traveler can only access own bookings", forbidden.text)


_VARIANTS, _CONFIG_ERROR = discover_live_variants()

if _CONFIG_ERROR:
    class VariantSelectionError(unittest.TestCase):
        @classmethod
        def setUpClass(cls) -> None:
            raise unittest.SkipTest(_CONFIG_ERROR)
else:
    for _variant in _VARIANTS:
        _class_name = "".join(
            part.title().replace("_", "")
            for part in (
                _variant.environment.id,
                _variant.backend.id,
                _variant.oauth.id,
                "e2e_test",
            )
        )
        globals()[_class_name] = type(
            _class_name,
            (LiveVariantCase, WebUiE2ETestMixin),
            {"VARIANT": _variant},
        )
