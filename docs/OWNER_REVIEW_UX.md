# Owner review: UX v2 (U4)

Work does not wait for this page.

**What changes for you:** a new booking wizard, a Bid Room for the customer, a full-screen incoming load card for the driver, a dispatch monitor for admin. Old screens stay behind the switch `uiV2`.

**Decisions I took (see DECISIONS.md):** three modes (Turant, Boli, Schedule); rings 3 / 7 / 15 km; accept time 30 s; bid window 10 minutes; bid price 30% to 300% of the estimate; auto-accept works only while the customer app is open.

**Please check on a phone:** 1) book in each mode, 2) driver receives a card, accepts or bids, 3) two drivers accept together, 4) Hindi and big text, 5) Bilty button on a booking.

**Switches:** `uiV2` ON (default). `dispatchV2` stays OFF until the new Firestore rules are published; then turn it on with `rateRange` if you want price ranges.

**Cannot be done without you:** deploy of rules and indexes, push notifications for background alerts, real sound review on a device.
