import AudioToolbox
import CoreAudio

public enum SystemVolumeController {
    public static func currentVolume() -> Float32? {
        guard let device = defaultOutputDevice(),
              var address = volumeAddress(for: device) else { return nil }
        var value = Float32.zero
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
            return nil
        }
        return min(max(value, 0), 1)
    }

    @discardableResult
    public static func adjust(by delta: Float32) -> Float32? {
        guard let device = defaultOutputDevice(),
              var address = volumeAddress(for: device),
              var value = currentVolume() else { return nil }
        value = min(max(value + delta, 0), 1)
        let size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr else {
            return nil
        }
        return value
    }

    @discardableResult
    public static func toggleMute() -> Bool? {
        guard let device = defaultOutputDevice() else { return nil }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr else {
            return nil
        }
        muted = muted == 0 ? 1 : 0
        guard AudioObjectSetPropertyData(device, &address, 0, nil, size, &muted) == noErr else {
            return nil
        }
        return muted != 0
    }

    private static func defaultOutputDevice() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        ) == noErr, device != kAudioObjectUnknown else { return nil }
        return device
    }

    private static func volumeAddress(for device: AudioObjectID) -> AudioObjectPropertyAddress? {
        for selector in [
            kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            kAudioDevicePropertyVolumeScalar,
        ] {
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var settable = DarwinBoolean(false)
            if AudioObjectHasProperty(device, &address),
               AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
               settable.boolValue {
                return address
            }
        }
        return nil
    }
}
