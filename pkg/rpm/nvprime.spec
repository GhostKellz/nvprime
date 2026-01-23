Name:           nvprime
Version:        0.1.0
Release:        1%{?dist}
Summary:        NVIDIA subsystem layer for Linux gaming

License:        MIT
URL:            https://github.com/ghostkellz/nvprime
Source0:        %{name}-%{version}.tar.gz

BuildRequires:  zig >= 0.16.0
BuildRequires:  cuda-toolkit
Requires:       nvidia-driver >= 590
Requires:       vulkan-loader
Requires:       libdrm

%description
NVPrime provides a comprehensive NVIDIA subsystem layer for Linux,
designed as AMD's ROCm equivalent but broader in scope. Features include:

* GPU fundamentals (clocks, P-states, voltage monitoring)
* Power and thermal management
* Display pipeline (VRR, HDR, multi-monitor)
* DLSS 4.5 integration with Dynamic Multi-Frame Generation
* Low-latency gaming via Reflex integration
* Game streaming infrastructure

%package libs
Summary:        NVPrime shared libraries
Requires:       %{name} = %{version}-%{release}

%description libs
Shared libraries for NVPrime integration with other applications.

%package devel
Summary:        NVPrime development files
Requires:       %{name}-libs = %{version}-%{release}

%description devel
Development files for NVPrime C API integration.

%prep
%autosetup

%build
zig build -Doptimize=ReleaseFast -Dnvml=true

%install
rm -rf $RPM_BUILD_ROOT

# Binary
install -Dm755 zig-out/bin/nvprime %{buildroot}%{_bindir}/nvprime

# Library
install -Dm755 zig-out/lib/libnvprime.so %{buildroot}%{_libdir}/libnvprime.so

# Header
install -Dm644 include/nvprime.h %{buildroot}%{_includedir}/nvprime.h

# Systemd service
install -Dm644 pkg/systemd/nvprime.service %{buildroot}%{_unitdir}/nvprime.service

# Udev rules
install -Dm644 pkg/udev/99-nvprime.rules %{buildroot}%{_udevrulesdir}/99-nvprime.rules

# Config
install -Dm644 pkg/config/nvprime.conf %{buildroot}%{_sysconfdir}/nvprime/nvprime.conf

# Shell completions
install -Dm644 pkg/completions/nvprime.bash %{buildroot}%{_datadir}/bash-completion/completions/nvprime
install -Dm644 pkg/completions/nvprime.zsh %{buildroot}%{_datadir}/zsh/site-functions/_nvprime
install -Dm644 pkg/completions/nvprime.fish %{buildroot}%{_datadir}/fish/vendor_completions.d/nvprime.fish

# Documentation
install -Dm644 README.md %{buildroot}%{_docdir}/%{name}/README.md
install -Dm644 LICENSE %{buildroot}%{_licensedir}/%{name}/LICENSE

%files
%license LICENSE
%doc README.md
%{_bindir}/nvprime
%{_unitdir}/nvprime.service
%{_udevrulesdir}/99-nvprime.rules
%config(noreplace) %{_sysconfdir}/nvprime/nvprime.conf
%{_datadir}/bash-completion/completions/nvprime
%{_datadir}/zsh/site-functions/_nvprime
%{_datadir}/fish/vendor_completions.d/nvprime.fish

%files libs
%{_libdir}/libnvprime.so

%files devel
%{_includedir}/nvprime.h

%changelog
* Tue Jan 21 2025 Christopher Kelley <ckelley@ghostkellz.sh> - 0.1.0-1
- Initial package
