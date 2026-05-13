import React, { useState } from 'react';

interface AttendanceRecord {
  worker: string;
  project: string;
  status: 'Present' | 'Late' | 'Absent';
  checkIn: string;
  checkOut: string;
  hours: string;
  method: string;
}

const AttendanceTracking: React.FC = () => {
  const [selectedProject, setSelectedProject] = useState('All Projects');
  const [selectedStatus, setSelectedStatus] = useState('All Status');

  const attendanceRecords: AttendanceRecord[] = [
    {
      worker: 'Ali Hassan',
      project: 'Kuala Lumpur Tower Block A',
      status: 'Present',
      checkIn: '07:12',
      checkOut: '17:45',
      hours: '10.5h',
      method: 'Geofence'
    },
    {
      worker: 'Boon Chong Tan',
      project: 'Kuala Lumpur Tower Block A',
      status: 'Present',
      checkIn: '07:28',
      checkOut: '17:30',
      hours: '10h',
      method: 'Geofence'
    },
    {
      worker: 'Mohamad Farid',
      project: 'Petaling Jaya Residential Complex',
      status: 'Absent',
      checkIn: '—',
      checkOut: '—',
      hours: '—',
      method: '—'
    }
  ];

  const projects = [
    { name: 'Kuala Lumpur Tower Block A', workers: 47, status: 'Active' },
    { name: 'Petaling Jaya Residential Complex', workers: 31, status: 'Active' },
    { name: 'Penang Bridge Maintenance', workers: 18, status: 'Active' },
    { name: 'Iskandar Puteri Industrial Hub', workers: 55, status: 'Active' }
  ];

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'Present':
        return 'bg-green-100 text-green-800';
      case 'Late':
        return 'bg-yellow-100 text-yellow-800';
      case 'Absent':
        return 'bg-red-100 text-red-800';
      default:
        return 'bg-gray-100 text-gray-800';
    }
  };

  return (
    <div className="min-h-screen bg-gray-50">
      {/* Header */}
      <div className="bg-white border-b border-gray-200 px-8 py-6 flex justify-between items-center">
        <div>
          <h1 className="text-3xl font-bold text-gray-900">Attendance Tracking</h1>
          <p className="text-gray-600 mt-1">📅 Monday, 12 May 2025 — GPS Geofenced</p>
        </div>
        <button className="flex items-center gap-2 text-gray-700 hover:text-gray-900">
          📤 Export
        </button>
      </div>

      {/* Main Content */}
      <div className="p-8">
        {/* Attendance Summary */}
        <div className="grid grid-cols-4 gap-6 mb-8">
          <div className="bg-white rounded-lg shadow p-6">
            <p className="text-gray-600 text-sm">Total</p>
            <p className="text-4xl font-bold text-gray-900 mt-2">12</p>
            <p className="text-gray-600 text-xs mt-2">registered</p>
          </div>
          <div className="bg-white rounded-lg shadow p-6">
            <p className="text-gray-600 text-sm">Present</p>
            <p className="text-4xl font-bold text-green-600 mt-2">8</p>
            <p className="text-gray-600 text-xs mt-2">67% attendance</p>
          </div>
          <div className="bg-white rounded-lg shadow p-6">
            <p className="text-gray-600 text-sm">Late</p>
            <p className="text-4xl font-bold text-yellow-600 mt-2">2</p>
            <p className="text-gray-600 text-xs mt-2">after 07:30</p>
          </div>
          <div className="bg-white rounded-lg shadow p-6">
            <p className="text-gray-600 text-sm">Absent</p>
            <p className="text-4xl font-bold text-red-600 mt-2">2</p>
            <p className="text-gray-600 text-xs mt-2">not on site</p>
          </div>
        </div>

        {/* Attendance Rate Progress Bar */}
        <div className="bg-white rounded-lg shadow p-6 mb-8">
          <h2 className="font-bold text-gray-900 mb-4">Today's Attendance Rate — All Projects</h2>
          <div className="flex gap-4">
            <div className="flex-1 bg-gray-200 rounded-full h-4 overflow-hidden">
              <div className="flex h-full">
                <div className="bg-green-500" style={{ width: '67%' }}></div>
                <div className="bg-yellow-500" style={{ width: '17%' }}></div>
                <div className="bg-red-500" style={{ width: '16%' }}></div>
              </div>
            </div>
          </div>
          <div className="flex gap-6 mt-3 text-sm">
            <div className="flex items-center gap-2">
              <div className="w-3 h-3 bg-green-500 rounded-full"></div>
              <span>• Present 67%</span>
            </div>
            <div className="flex items-center gap-2">
              <div className="w-3 h-3 bg-yellow-500 rounded-full"></div>
              <span>• Late 17%</span>
            </div>
            <div className="flex items-center gap-2">
              <div className="w-3 h-3 bg-red-500 rounded-full"></div>
              <span>• Absent 17%</span>
            </div>
          </div>
        </div>

        {/* Projects Overview */}
        <h2 className="text-xl font-bold text-gray-900 mb-4">Projects with Active Geofencing</h2>
        <div className="grid grid-cols-4 gap-6 mb-8">
          {projects.map((project) => (
            <div key={project.name} className="bg-white rounded-lg shadow p-6 text-center">
              <div className="flex items-center justify-center gap-2 mb-2">
                <span className="text-2xl">📍</span>
                <span className="text-green-600 text-sm font-semibold">• Active</span>
              </div>
              <h3 className="font-bold text-gray-900 mb-2 text-sm">{project.name}</h3>
              <p className="text-blue-600 font-bold text-lg">{project.workers} workers tracked</p>
              <p className="text-gray-600 text-xs mt-2">Radius: 200m</p>
            </div>
          ))}
        </div>

        {/* Detailed Attendance Table */}
        <div className="bg-white rounded-lg shadow overflow-hidden">
          <div className="p-6 border-b border-gray-200">
            <div className="flex gap-4 mb-4">
              <input
                type="text"
                placeholder="Search worker..."
                className="flex-1 px-4 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-orange-500"
              />
              <select
                value={selectedProject}
                onChange={(e) => setSelectedProject(e.target.value)}
                className="px-4 py-2 border border-gray-300 rounded-lg focus:outline-none"
              >
                <option>All Projects</option>
                {projects.map((p) => (
                  <option key={p.name}>{p.name}</option>
                ))}
              </select>
              <select
                value={selectedStatus}
                onChange={(e) => setSelectedStatus(e.target.value)}
                className="px-4 py-2 border border-gray-300 rounded-lg focus:outline-none"
              >
                <option>All Status</option>
                <option>Present</option>
                <option>Late</option>
                <option>Absent</option>
              </select>
            </div>
          </div>

          {/* Table */}
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-gray-100">
                <tr>
                  <th className="px-6 py-3 text-left text-sm font-semibold text-gray-700">WORKER</th>
                  <th className="px-6 py-3 text-left text-sm font-semibold text-gray-700">PROJECT</th>
                  <th className="px-6 py-3 text-left text-sm font-semibold text-gray-700">STATUS</th>
                  <th className="px-6 py-3 text-left text-sm font-semibold text-gray-700">CHECK IN</th>
                  <th className="px-6 py-3 text-left text-sm font-semibold text-gray-700">CHECK OUT</th>
                  <th className="px-6 py-3 text-left text-sm font-semibold text-gray-700">HOURS</th>
                  <th className="px-6 py-3 text-left text-sm font-semibold text-gray-700">METHOD</th>
                </tr>
              </thead>
              <tbody>
                {attendanceRecords.map((record, idx) => (
                  <tr key={idx} className="border-t border-gray-200 hover:bg-gray-50">
                    <td className="px-6 py-4 text-sm text-gray-900">{record.worker}</td>
                    <td className="px-6 py-4 text-sm text-gray-600">{record.project}</td>
                    <td className="px-6 py-4">
                      <span className={`px-3 py-1 rounded-full text-xs font-semibold ${getStatusColor(record.status)}`}>
                        ✓ {record.status}
                      </span>
                    </td>
                    <td className="px-6 py-4 text-sm text-gray-900">{record.checkIn}</td>
                    <td className="px-6 py-4 text-sm text-gray-900">{record.checkOut}</td>
                    <td className="px-6 py-4 text-sm text-gray-900">{record.hours}</td>
                    <td className="px-6 py-4 text-sm text-blue-600">📍 {record.method}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  );
};

export default AttendanceTracking;