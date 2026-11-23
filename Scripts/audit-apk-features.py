#!/usr/bin/env python3
"""Inventory every packaged navigation graph without treating declarations as working services."""
import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
COVERAGE = {
    'home_graph': ('partial_native', 'App/Views/DashboardViews.swift', 'Home, score details, day navigation, recovery calendar, activities and trend windows; original Home content is server-fed.'),
    'health_graph': ('partial_native', 'App/Views/DashboardViews.swift', 'Recorded health measurements and personalized age display; proprietary aging, pace and clinical services are unavailable.'),
    'core_details_graph': ('partial_native', 'App/Views/DetailViews.swift', 'Sleep/Recovery/Strain details, stages, reported efficiency/consistency/debt, chart selection and trends; not every proprietary insight is available.'),
    'stress_monitor_graph': ('service_gap', 'App/Views/ReferenceComponents.swift', 'Presentation exists; proprietary stress scores/time series are not inferred from HR.'),
    'stress_session_graph': ('not_implemented', None, 'Guided stress sessions and vendor stress scoring are not implemented.'),
    'profile_graph': ('partial_native', 'App/Pulse/PulseHomePanels.swift', 'Local profile, chosen age/streak, recorded highlights and exports; vendor achievement/ranking services are absent.'),
    'profile_levels_graph': ('partial_native', 'App/Pulse/PulseHomePanels.swift', 'Existing local presentation does not reproduce WHOOP level entitlements.'),
    'new_journal_nav_graph': ('partial_native', 'App/Views/DetailViews.swift', 'Local caffeine/alcohol/late-meal journal and notes; the remote behavior catalog and vendor impact model are absent.'),
    'memberdataexport_nav_graph': ('native_local', 'App/Views/MeasurementExportView.swift', 'Saved-data JSON/CSV, full backups and raw tracker archives; requesting a vendor account archive is a separate service.'),
    'settings_graph_redesign': ('partial_native', 'App/Views/SecondaryViews.swift', 'Local preferences, language, device, data and account-bridge settings; billing and account administration remain provider services.'),
    'community_graph': ('service_gap', 'App/Views/SecondaryViews.swift', 'Local activity history exists. WHOOP teams, leaderboards, friends, referrals and family billing are not connected.'),
    'sage_graph': ('service_gap', 'App/Views/ReferenceComponents.swift', 'Recorded-day review is not WHOOP’s proprietary Coach chat service.'),
    'advanced_labs_graph': ('service_gap', None, 'Lab ordering, clinician review and provider biomarker integration require the vendor service.'),
    'sleep_coach_graph': ('partial_native', 'App/Views/DetailViews.swift', 'Reported sleep need/debt and history are displayed; band alarm scheduling and vendor coaching are not implemented.'),
    'strength_trainer_graph': ('partial_native', 'App/WorkoutRecorder.swift', 'Real HR workout recording and optional labeled local estimates; muscular load, set recognition and native MSK model are not implemented.'),
    'weightlifting_nav_graph': ('partial_native', 'App/WorkoutRecorder.swift', 'Same strength boundary; no invented rep/set metrics.'),
    'core_details_weightlifting_activity_details_graph': ('partial_native', 'App/Views/DetailViews.swift', 'Recorded activities are available; vendor muscular-load details are absent.'),
    'training_activity_settings_graph': ('partial_native', 'App/Views/DetailViews.swift', 'Local activity names/durations and HR limits; not all sport-specific device settings.'),
    'onboarding_stories_graph': ('partial_native', 'App/WHOOPApp.swift', 'Single local setup, packaged loading motion and original intro video; vendor login/activation flows are not reproduced.'),
    'user_journey_graph': ('partial_native', 'App/WHOOPApp.swift', 'Local setup and optional public-account bridge; remote activation/membership routing remains unavailable.'),
    'proper_fit_nav_graph': ('not_implemented', None, 'The original fit-education flow has not been rebuilt.'),
    'change_password_graph': ('service_gap', 'App/Views/AccountView.swift', 'An account bridge does not implement WHOOP password changes.'),
    'download_graph': ('partial_native', 'App/DeviceModel.swift', 'Supported history transfer, storage-before-acknowledgement, raw export and HR/R-R projection; physical device compatibility is not verified.'),
    'design_showcase_graph': ('developer_only', None, 'Packaged design-system demonstration; not treated as a member feature.'),
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--apk', type=Path)
    args = parser.parse_args()
    path = ROOT / 'design/apk/navigation-declarations.json'
    declarations = json.loads(path.read_text())
    graphs = []
    for entry in declarations:
        name = Path(entry['member']).stem
        status, source, note = COVERAGE.get(name, ('not_implemented', None, 'No implemented route verified.'))
        destinations = []
        actions = 0
        for node in entry['nodes']:
            if node['tag'] == 'action': actions += 1
            if node['tag'] not in ('fragment', 'activity', 'dialog'): continue
            attrs = node['attributes']
            identifier = attrs.get('id', {})
            destinations.append({'id': identifier.get('name') if isinstance(identifier, dict) else identifier,
                                 'class': attrs.get('name'), 'label': attrs.get('label'),
                                 'coverage': status, 'implementation': source})
        graphs.append({'graph': name, 'coverage': status, 'implementation': source,
                       'note': note, 'actions': actions, 'destinations': destinations})
    output = {'source': 'User-supplied WHOOP Android 5.444.1 / 431134',
              'scope': 'All 24 packaged XML navigation graphs, not all Compose/server-fed UI or live service behavior.',
              'declarations_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
              'graph_count': len(graphs), 'destination_count': sum(len(g['destinations']) for g in graphs),
              'action_count': sum(g['actions'] for g in graphs),
              'coverage_by_graph': dict(Counter(g['coverage'] for g in graphs)),
              'graphs': graphs}
    if args.apk:
        with args.apk.open('rb') as data: output['apk_sha256'] = hashlib.file_digest(data, 'sha256').hexdigest()
    target = ROOT / 'design/apk/feature-inventory.json'
    target.write_text(json.dumps(output, indent=2) + '\n')
    print(json.dumps({k: output[k] for k in ['graph_count', 'destination_count', 'action_count', 'coverage_by_graph']}, indent=2))

if __name__ == '__main__': main()
