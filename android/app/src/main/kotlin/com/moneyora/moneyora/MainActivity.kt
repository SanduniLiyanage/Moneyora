package com.moneyora.moneyora

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity, not FlutterActivity: local_auth's biometric
// prompt is a DialogFragment, which needs a FragmentActivity host.
// NFR-SEC-004.
class MainActivity : FlutterFragmentActivity()
