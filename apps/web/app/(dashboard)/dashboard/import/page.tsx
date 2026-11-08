import type { Metadata } from "next";
import { getMe } from "@/app/(dashboard)/_lib/api";
import { PageHead, Section } from "@/app/(dashboard)/_components/ui";
import { ImportFlow } from "./ImportFlow";

export const metadata: Metadata = { title: "Import" };

export default async function ImportPage() {
  const me = await getMe();
  return (
    <>
      <PageHead title="Import your register">
        Upload the estate&rsquo;s existing list of homes and residents. Nothing is saved until you have checked it and pressed Commit.
      </PageHead>

      {me.role !== "admin" ? (
        <p className="dash-msg dash-msg--warn">Only an estate admin can import the register.</p>
      ) : (
        <div className="dash-split">
          <ImportFlow />
          <Section title="What the file should look like">
            <p className="dash-muted">A CSV or Excel file (.xlsx), up to 2 MB and 5,000 rows. The first row must be the column headings. Column order does not matter.</p>
            <table className="dash-table dash-table--compact">
              <thead>
                <tr>
                  <th scope="col">Column</th>
                  <th scope="col">Also accepted</th>
                  <th scope="col">Notes</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td>Zone</td>
                  <td>Block, Phase</td>
                  <td>Required</td>
                </tr>
                <tr>
                  <td>Street</td>
                  <td>Close, Court, Road, Avenue, Crescent</td>
                  <td>Required</td>
                </tr>
                <tr>
                  <td>House</td>
                  <td>Home, Flat, Unit, Plot, House number</td>
                  <td>Required</td>
                </tr>
                <tr>
                  <td>Resident</td>
                  <td>Name, Occupant, Owner</td>
                  <td>Needed if a phone is given</td>
                </tr>
                <tr>
                  <td>Phone</td>
                  <td>Phone number, Mobile, GSM</td>
                  <td>Up to 3, separated by / or ;</td>
                </tr>
                <tr>
                  <td>Contact</td>
                  <td>Contact pref, Preference</td>
                  <td>whatsapp, sms or call</td>
                </tr>
                <tr>
                  <td>Callback</td>
                  <td>Callback required</td>
                  <td>yes or no</td>
                </tr>
              </tbody>
            </table>
            <p className="dash-muted dash-small">
              Zones, streets and homes that already exist are reused, not duplicated. A resident already registered at the same home is skipped.
            </p>
          </Section>
        </div>
      )}
    </>
  );
}
