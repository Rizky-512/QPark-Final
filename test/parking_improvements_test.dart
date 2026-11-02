import 'package:flutter_test/flutter_test.dart';
import 'package:qpark/data/remote_repository.dart';
import 'package:qpark/domain/customer_status.dart';
import 'package:qpark/domain/operational_status.dart';
import 'package:qpark/domain/parking_cost.dart';
import 'package:qpark/domain/parking_receipt.dart';

Json session() => {
  'id': 'TICKET-1',
  'plate': 'B123AB',
  'vehicle_type': 'MOBIL',
  'state': 'IN_AREA',
  'entered_at': 1000,
  'hourly_rate': 7000,
  'invoices': <Json>[],
  'window_status': 'NONE',
};
CustomerStatus status(
  Json? ticket, {
  bool online = true,
  bool pending = false,
  bool hasVehicle = true,
  bool loading = false,
}) => CustomerStatus.resolve(
  hasVehicle: hasVehicle,
  online: online,
  loading: loading,
  pending: pending,
  ticket: ticket,
  now: 2000,
);

void main() {
  test(
    'Customer actions follow ownership, connectivity and uncertain payments',
    () {
      expect(status(null, hasVehicle: false).action, CustomerAction.addVehicle);
      expect(status(null).action, CustomerAction.link);
      expect(status(session(), online: false).action, CustomerAction.refresh);
      expect(
        status(null, online: false, loading: true).title,
        'Memuat status parkir',
      );
      expect(status(session(), pending: true).action, CustomerAction.reconcile);
      expect(status(session()).action, CustomerAction.payment);
    },
  );
  test('Expired authorization does not keep showing exit approval', () {
    final s = session()
      ..addAll({
        'state': 'EXIT_AUTHORIZED',
        'authorization': {'expires_at': 2001},
      });
    expect(status(s).title, 'Menunggu kendaraan keluar');
    s['authorization'] = {'expires_at': 2000};
    expect(status(s).action, CustomerAction.payment);
    s.addAll({
      'window_status': 'VALID',
      'window': {'deadline': 2000},
    });
    expect(status(s).action, CustomerAction.exitQr);
    s['state'] = 'COMPLETED';
    expect(status(s).action, CustomerAction.history);
  });
  test('Estimate matches server minimum and full-hour boundaries', () {
    for (final seconds in [0, 3599, 3600, 6000, 7199]) {
      expect(ParkingCost.fromSession(session(), 1000.0 + seconds).amount, 7000);
    }
    expect(ParkingCost.fromSession(session(), 8200).amount, 14000);
    expect(ParkingCost.fromSession(session(), 900).seconds, 0);
  });
  test('Valid invoice overrides estimate, expired quote does not', () {
    final s = session()
      ..['invoices'] = <Json>[
        {'state': 'PENDING', 'amount': 7000, 'expires_at': 9000},
      ];
    expect(ParkingCost.fromSession(s, 8200).amount, 7000);
    expect(ParkingCost.fromSession(s, 9000).amount, 14000);
    expect(ParkingCost.fromSession(s, 9000).serverInvoice, false);
  });
  test('Paid ticket adds one penalty only after deadline', () {
    final s = session()
      ..addAll({
        'amount_paid': 7000,
        'window': {'deadline': 2000},
      });
    expect(ParkingCost.fromSession(s, 2000).amount, 0);
    expect(ParkingCost.fromSession(s, 2001).amount, 7000);
    expect(ParkingCost.fromSession(s, 2001).additional, true);
    s['state'] = 'COMPLETED';
    expect(ParkingCost.fromSession(s, 10000).amount, 0);
  });
  test('Officer filters respect pending invoices and expired approval', () {
    final s = session();
    expect(operationalStatus(s, 2000), OperationalStatus.unpaid);
    s.addAll({
      'window_status': 'VALID',
      'window': {'deadline': 2000},
    });
    expect(operationalStatus(s, 2000), OperationalStatus.paid);
    expect(operationalStatus(s, 2001), OperationalStatus.unpaid);
    s.addAll({
      'state': 'EXIT_AUTHORIZED',
      'authorization': {'expires_at': 2100},
    });
    expect(operationalStatus(s, 2001), OperationalStatus.authorized);
    expect(operationalStatus(s, 2100), OperationalStatus.unpaid);
    s['invoices'] = <Json>[
      {'state': 'PENDING'},
    ];
    s['state'] = 'IN_AREA';
    expect(operationalStatus(s, 2000), OperationalStatus.unpaid);
  });
  test(
    'Receipt includes confirmed payments only and excludes access tokens',
    () {
      final s = session()
        ..addAll({
          'exit_qr': 'SECRET-EXIT',
          'customer_key': 'SECRET-CUSTOMER',
          'invoices': <Json>[
            {
              'id': 'PAID-1',
              'state': 'PAID',
              'amount': 7000,
              'hours': 1,
              'payment_method': 'QR_SIMULASI',
              'paid_at': 2000,
            },
            {'id': 'UNPAID-2', 'state': 'PENDING', 'amount': 14000},
          ],
        });
      final text = ParkingReceipt.fromSession(s).text;
      expect(
        text,
        contains('SIMULASI - pembayaran QR tidak memindahkan uang nyata'),
      );
      expect(text, contains('TOTAL TERCATAT: Rp7.000'));
      expect(text, isNot(contains('SECRET')));
      expect(text, isNot(contains('UNPAID-2')));
      expect(text, contains('WIB'));
    },
  );
  test(
    'Manual receipt preserves received and change; unpaid has no receipt',
    () {
      final s = session();
      expect(ParkingReceipt.available(s), false);
      expect(() => ParkingReceipt.fromSession(s), throwsStateError);
      s['invoices'] = <Json>[
        {
          'id': 'CASH-1',
          'state': 'PAID',
          'amount': 7000,
          'payment_method': 'MANUAL',
          'received': 10000,
          'change_amount': 3000,
        },
      ];
      final text = ParkingReceipt.fromSession(s).text;
      expect(text, contains('Diterima: Rp10.000 | Kembalian: Rp3.000'));
      expect(text, isNot(contains('QR SIMULASI')));
    },
  );
}
