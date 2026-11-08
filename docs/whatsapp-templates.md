# WhatsApp message templates

Messages Gatelog starts (not replies inside a conversation the resident opened in the last
24 hours) must use templates Meta has approved. Submit these as the first batch, category
**Utility**, language **English**. Names and parameter order must match
`apps/api/app/messaging.py` (`TEMPLATES`).

| Name | Body | Parameters |
|---|---|---|
| `gatelog_gate_code` | {{1}}: Gate code {{3}} for {{2}}, valid {{4}}. | estate, guest, code, valid_until |
| `gatelog_arrival` | {{1}}: {{2}} is in. {{3}}, {{4}}. | estate, guest, gate, time |
| `gatelog_departure` | {{1}}: {{2}} has left. {{3}}, {{4}}. | estate, guest, gate, time |
| `gatelog_overstay` | {{1}}: Is {{2}} still with you? Reply 1 staying (until when?), 2 already left. | estate, guest |
| `gatelog_night_list` | {{1}}: Gatelog night list: {{2}} guests still inside past their time. {{3}} | estate, count, summary |
| `gatelog_shuttle_on_way` | {{1}}: {{2}} is on the way on {{3}} to take you from {{4}}. | estate, rider, shuttle, from |
| `gatelog_parcel_on_way` | {{1}}: {{2}} is on its way to you from {{3}} on the estate shuttle. | estate, parcel, from |

Every template starts with the estate's name ({{1}}, the estate's short name or full name),
because every estate shares the one Gatelog number and the sender always shows as Gatelog.

The SOS contact templates (Phase 2) go in the same batch, so approval does not hold up SOS
later. Until the estate's WhatsApp Business account is approved (`whatsapp_enabled` in the
estate settings), every resident gets SMS.
